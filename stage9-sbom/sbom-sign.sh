#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# sbom-sign.sh — Stage 9: SBOM Generation & Image Signing
# ─────────────────────────────────────────────────────────────────────────────
# Generates an SBOM from a container image using Trivy, signs the image
# with cosign, and attaches the SBOM as an attestation.
#
# Usage:
#   ./sbom-sign.sh [options]
#
# Options:
#   -i, --image <tag>         Image to process (required)
#   -o, --output <dir>        Output directory for SBOM and metadata
#   -f, --format <fmt>        SBOM format: cyclonedx or spdx-json (default: cyclonedx)
#   -k, --key <path>          Cosign private key for signing
#   --keyless                 Use keyless signing (Sigstore/Fulcio)
#   --skip-sign               Generate SBOM only, skip signing
#   --registry <url>          Push image to registry before signing
#   --registry-user <user>    Registry username (or set REGISTRY_USER env var)
#   --registry-pass <pass>    Registry password/token (or set REGISTRY_PASS env var)
#   --push-sbom               Also push SBOM as OCI artifact to registry
#   -h, --help                Show this help message
#
# Environment Variables:
#   REGISTRY_USER             Registry username (alternative to --registry-user)
#   REGISTRY_PASS             Registry password or API token (alternative to --registry-pass)
#
# Secrets File:
#   Reads .secrets from current directory or /workspace (KEY=VALUE format)
#   Supports: REGISTRY_USER, REGISTRY_PASS, JFROG_USER, JFROG_TOKEN
#
# Examples:
#   ./sbom-sign.sh --image myapp:1.0.0 --output /artifacts/stage9 --skip-sign
#   ./sbom-sign.sh --image myapp:1.0.0 --output /artifacts/stage9 --keyless
#   ./sbom-sign.sh --image myapp:1.0.0 --key cosign.key --output /artifacts/stage9
#   ./sbom-sign.sh --image myapp:1.0.0 --registry jfrog.io/docker-local --keyless
#   ./sbom-sign.sh --image myapp:1.0.0 --registry jfrog.io/docker-local --registry-user deploy --registry-pass $TOKEN --keyless --push-sbom
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m'
    CYAN='\033[0;36m' DIM='\033[2m' WHITE='\033[1;37m' RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' DIM='' WHITE='' RESET=''
fi

# ── Defaults ─────────────────────────────────────────────────────────────────
IMAGE=""
OUTPUT_DIR=""
SBOM_FORMAT="cyclonedx"
COSIGN_KEY=""
KEYLESS=false
SKIP_SIGN=false
REGISTRY=""
REGISTRY_USER="${REGISTRY_USER:-}"
REGISTRY_PASS="${REGISTRY_PASS:-}"
PUSH_SBOM=false
EXIT_CODE=0

# ── Load secrets file if present ─────────────────────────────────────────────
# Looks for .secrets in current directory or /workspace
# Format: KEY=VALUE (one per line, supports REGISTRY_USER and REGISTRY_PASS)
for secrets_path in "./.secrets" "/workspace/.secrets"; do
    if [[ -f "$secrets_path" ]]; then
        echo "Loading credentials from $secrets_path"
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ -z "$key" || "$key" =~ ^# ]] && continue
            # Trim whitespace
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            case "$key" in
                REGISTRY_USER) REGISTRY_USER="$value" ;;
                REGISTRY_PASS) REGISTRY_PASS="$value" ;;
                JFROG_USER)    REGISTRY_USER="$value" ;;
                JFROG_TOKEN)   REGISTRY_PASS="$value" ;;
            esac
        done < "$secrets_path"
        break
    fi
done

# ── Argument Parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--image)      IMAGE="$2"; shift 2 ;;
        -o|--output)     OUTPUT_DIR="$2"; shift 2 ;;
        -f|--format)     SBOM_FORMAT="$2"; shift 2 ;;
        -k|--key)        COSIGN_KEY="$2"; shift 2 ;;
        --keyless)       KEYLESS=true; shift ;;
        --skip-sign)     SKIP_SIGN=true; shift ;;
        --registry)      REGISTRY="$2"; shift 2 ;;
        --registry-user) REGISTRY_USER="$2"; shift 2 ;;
        --registry-pass) REGISTRY_PASS="$2"; shift 2 ;;
        --push-sbom)     PUSH_SBOM=true; shift ;;
        -h|--help)
            sed -n '2,/^# ──/{ /^# ──/d; s/^# \?//p; }' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Helpers ──────────────────────────────────────────────────────────────────
banner() {
    local line
    line=$(printf '─%.0s' {1..60})
    echo -e "\n${CYAN}${line}${RESET}"
    echo -e "  ${CYAN}$1${RESET}"
    echo -e "${CYAN}${line}${RESET}"
}

# ── Validation ───────────────────────────────────────────────────────────────
banner "Stage 9: SBOM & Signing"

if [[ -z "$IMAGE" ]]; then
    echo -e "  ${RED}✗ --image is required${RESET}"
    exit 1
fi

echo -e "  ${DIM}Image:       ${IMAGE}${RESET}"
echo -e "  ${DIM}SBOM format: ${SBOM_FORMAT}${RESET}"
echo -e "  ${DIM}Skip sign:   ${SKIP_SIGN}${RESET}"
if [[ -n "$REGISTRY" ]]; then
    echo -e "  ${DIM}Registry:    ${REGISTRY}${RESET}"
fi

if ! command -v trivy &>/dev/null; then
    echo -e "  ${RED}✗ trivy not found in PATH${RESET}"
    exit 1
fi

if ! $SKIP_SIGN && ! command -v cosign &>/dev/null; then
    echo -e "  ${RED}✗ cosign not found in PATH (use --skip-sign to skip signing)${RESET}"
    exit 1
fi

if ! $SKIP_SIGN && ! $KEYLESS && [[ -z "$COSIGN_KEY" ]]; then
    echo -e "  ${RED}✗ Must specify --key or --keyless for signing${RESET}"
    exit 1
fi

START_TIME=$SECONDS

if [[ -n "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
fi

# ── Determine target image ───────────────────────────────────────────────────
TARGET_IMAGE="$IMAGE"

# If registry specified, login and push
if [[ -n "$REGISTRY" ]]; then
    # Extract registry host for login
    REGISTRY_HOST="${REGISTRY%%/*}"

    # Login if credentials provided
    if [[ -n "$REGISTRY_USER" ]] && [[ -n "$REGISTRY_PASS" ]]; then
        banner "Authenticating to registry"
        echo -e "  ${WHITE}▶  Logging in to ${REGISTRY_HOST}${RESET}"

        set +e
        echo "$REGISTRY_PASS" | docker login "$REGISTRY_HOST" -u "$REGISTRY_USER" --password-stdin 2>&1 | sed 's/^/     /'
        LOGIN_RC=${PIPESTATUS[0]}
        set -e

        if [[ $LOGIN_RC -ne 0 ]]; then
            echo -e "  ${RED}✗ Login failed${RESET}"
            exit $LOGIN_RC
        fi
        echo -e "  ${GREEN}✓ Authenticated${RESET}"
    fi

    banner "Pushing image to registry"

    REMOTE_IMAGE="${REGISTRY}/${IMAGE##*/}"
    echo -e "  ${WHITE}▶  Tagging ${IMAGE} → ${REMOTE_IMAGE}${RESET}"

    docker tag "$IMAGE" "$REMOTE_IMAGE"

    echo -e "  ${WHITE}▶  Pushing ${REMOTE_IMAGE}${RESET}"
    set +e
    docker push "$REMOTE_IMAGE" 2>&1 | sed 's/^/     /'
    PUSH_RC=${PIPESTATUS[0]}
    set -e

    if [[ $PUSH_RC -ne 0 ]]; then
        echo -e "  ${RED}✗ Push failed${RESET}"
        exit $PUSH_RC
    fi

    echo -e "  ${GREEN}✓ Image pushed to ${REMOTE_IMAGE}${RESET}"
    TARGET_IMAGE="$REMOTE_IMAGE"
fi

# ── SBOM Generation ──────────────────────────────────────────────────────────
banner "Generating SBOM"

SBOM_EXT="json"
SBOM_FILE="sbom.${SBOM_FORMAT}.${SBOM_EXT}"

if [[ -n "$OUTPUT_DIR" ]]; then
    SBOM_PATH="${OUTPUT_DIR}/${SBOM_FILE}"
else
    SBOM_PATH="/tmp/${SBOM_FILE}"
fi

echo -e "  ${WHITE}▶  Generating ${SBOM_FORMAT} SBOM${RESET}"

TRIVY_FMT="$SBOM_FORMAT"
if [[ "$SBOM_FORMAT" == "spdx" ]]; then
    TRIVY_FMT="spdx-json"
fi

set +e
trivy image --format "$TRIVY_FMT" --output "$SBOM_PATH" "$TARGET_IMAGE" 2>&1 | sed 's/^/     /'
SBOM_RC=${PIPESTATUS[0]}
set -e

if [[ $SBOM_RC -ne 0 ]]; then
    echo -e "  ${RED}✗ SBOM generation failed${RESET}"
    EXIT_CODE=1
else
    SBOM_SIZE=$(du -h "$SBOM_PATH" | cut -f1)
    echo -e "  ${GREEN}✓ SBOM generated: ${SBOM_PATH} (${SBOM_SIZE})${RESET}"
fi

# ── Image Signing ────────────────────────────────────────────────────────────
if ! $SKIP_SIGN && [[ $EXIT_CODE -eq 0 ]]; then
    banner "Signing image"

    COSIGN_ARGS=("sign")

    if $KEYLESS; then
        echo -e "  ${WHITE}▶  Keyless signing via Sigstore/Fulcio${RESET}"
        export COSIGN_EXPERIMENTAL=1
        COSIGN_ARGS+=("--yes")
    else
        echo -e "  ${WHITE}▶  Signing with key: ${COSIGN_KEY}${RESET}"
        COSIGN_ARGS+=("--key" "$COSIGN_KEY")
    fi

    COSIGN_ARGS+=("$TARGET_IMAGE")

    set +e
    cosign "${COSIGN_ARGS[@]}" 2>&1 | sed 's/^/     /'
    SIGN_RC=${PIPESTATUS[0]}
    set -e

    if [[ $SIGN_RC -ne 0 ]]; then
        echo -e "  ${RED}✗ Signing failed${RESET}"
        EXIT_CODE=1
    else
        echo -e "  ${GREEN}✓ Image signed${RESET}"
    fi

    # ── Attach SBOM as attestation ───────────────────────────────────────────
    if [[ $SIGN_RC -eq 0 ]]; then
        banner "Attaching SBOM attestation"

        ATTEST_ARGS=("attest" "--predicate" "$SBOM_PATH" "--type" "$SBOM_FORMAT")

        if $KEYLESS; then
            ATTEST_ARGS+=("--yes")
        else
            ATTEST_ARGS+=("--key" "$COSIGN_KEY")
        fi

        ATTEST_ARGS+=("$TARGET_IMAGE")

        echo -e "  ${WHITE}▶  Attaching SBOM to image${RESET}"
        set +e
        cosign "${ATTEST_ARGS[@]}" 2>&1 | sed 's/^/     /'
        ATTEST_RC=${PIPESTATUS[0]}
        set -e

        if [[ $ATTEST_RC -ne 0 ]]; then
            echo -e "  ${RED}✗ Attestation failed${RESET}"
            EXIT_CODE=1
        else
            echo -e "  ${GREEN}✓ SBOM attached as attestation${RESET}"
        fi
    fi
fi

# ── Push SBOM to registry ───────────────────────────────────────────────────
if $PUSH_SBOM && [[ -n "$REGISTRY" ]] && [[ -f "$SBOM_PATH" ]]; then
    banner "Pushing SBOM to registry"

    SBOM_TAG="${TARGET_IMAGE}-sbom"
    echo -e "  ${WHITE}▶  Pushing SBOM as OCI artifact: ${SBOM_TAG}${RESET}"

    # Use ORAS if available, otherwise cosign attach
    if command -v oras &>/dev/null; then
        set +e
        oras push "$SBOM_TAG" "$SBOM_PATH:application/vnd.cyclonedx+json" 2>&1 | sed 's/^/     /'
        SBOM_PUSH_RC=${PIPESTATUS[0]}
        set -e
    elif command -v cosign &>/dev/null; then
        set +e
        cosign attach sbom --sbom "$SBOM_PATH" "$TARGET_IMAGE" 2>&1 | sed 's/^/     /'
        SBOM_PUSH_RC=${PIPESTATUS[0]}
        set -e
    else
        echo -e "  ${YELLOW}⚠  Neither oras nor cosign available for SBOM push${RESET}"
        SBOM_PUSH_RC=1
    fi

    if [[ $SBOM_PUSH_RC -ne 0 ]]; then
        echo -e "  ${YELLOW}⚠  SBOM push failed (non-fatal)${RESET}"
    else
        echo -e "  ${GREEN}✓ SBOM pushed to registry${RESET}"
    fi
fi

# ── Write metadata ───────────────────────────────────────────────────────────
ELAPSED=$(( SECONDS - START_TIME ))

if [[ -n "$OUTPUT_DIR" ]]; then
    cat > "${OUTPUT_DIR}/sbom-metadata.json" <<EOF
{
    "image": "${IMAGE}",
    "target_image": "${TARGET_IMAGE}",
    "registry": "${REGISTRY}",
    "pushed": $([ -n "$REGISTRY" ] && echo "true" || echo "false"),
    "sbom_format": "${SBOM_FORMAT}",
    "sbom_file": "${SBOM_PATH}",
    "sbom_pushed": ${PUSH_SBOM},
    "signed": $(! $SKIP_SIGN && echo "true" || echo "false"),
    "keyless": ${KEYLESS},
    "exit_code": ${EXIT_CODE},
    "elapsed_seconds": ${ELAPSED},
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    echo -e "\n  ${GREEN}✓ Metadata: ${OUTPUT_DIR}/sbom-metadata.json${RESET}"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
banner "Stage 9 Complete"
echo -e "  ${DIM}Elapsed: ${ELAPSED}s${RESET}"

if [[ $EXIT_CODE -ne 0 ]]; then
    echo -e "  ${RED}✗ Stage 9 FAILED${RESET}"
else
    echo -e "  ${GREEN}✓ Stage 9 PASSED${RESET}"
fi

exit $EXIT_CODE
