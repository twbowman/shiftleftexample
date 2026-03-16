#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# build.sh — Stage 1: Build container image
# ─────────────────────────────────────────────────────────────────────────────
# Builds a Docker image and optionally saves it as a tarball for downstream
# pipeline stages.
#
# Usage:
#   ./build.sh [options]
#
# Options:
#   -c, --context <dir>       Build context path (default: /workspace)
#   -f, --dockerfile <path>   Path to Dockerfile (default: <context>/Dockerfile)
#   -t, --tag <tag>           Image tag (default: app:latest)
#   -o, --output <dir>        Save image tarball to this directory
#   -a, --build-arg <arg>     Build argument (KEY=VALUE), can be repeated
#   --no-cache                Disable build cache
#   -h, --help                Show this help message
#
# Examples:
#   ./build.sh
#   ./build.sh --context ./myapp --tag myapp:1.0.0
#   ./build.sh --context ./myapp --tag myapp:1.0.0 --output /artifacts/stage1
#   ./build.sh --build-arg VERSION=1.0 --build-arg ENV=prod
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
BUILD_CONTEXT="/workspace"
DOCKERFILE=""
IMAGE_TAG="app:latest"
OUTPUT_DIR=""
NO_CACHE=false
BUILD_ARGS=()

# ── Argument Parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--context)    BUILD_CONTEXT="$2"; shift 2 ;;
        -f|--dockerfile) DOCKERFILE="$2"; shift 2 ;;
        -t|--tag)        IMAGE_TAG="$2"; shift 2 ;;
        -o|--output)     OUTPUT_DIR="$2"; shift 2 ;;
        -a|--build-arg)  BUILD_ARGS+=("--build-arg" "$2"); shift 2 ;;
        --no-cache)      NO_CACHE=true; shift ;;
        -h|--help)
            sed -n '2,/^# ──/{ /^# ──/d; s/^# \?//p; }' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Default dockerfile to context/Dockerfile
if [[ -z "$DOCKERFILE" ]]; then
    DOCKERFILE="${BUILD_CONTEXT}/Dockerfile"
fi

# ── Helpers ──────────────────────────────────────────────────────────────────
banner() {
    local line
    line=$(printf '─%.0s' {1..60})
    echo -e "\n${CYAN}${line}${RESET}"
    echo -e "  ${CYAN}$1${RESET}"
    echo -e "${CYAN}${line}${RESET}"
}

# ── Validation ───────────────────────────────────────────────────────────────
banner "Stage 1: Build"

echo -e "  ${DIM}Context:    ${BUILD_CONTEXT}${RESET}"
echo -e "  ${DIM}Dockerfile: ${DOCKERFILE}${RESET}"
echo -e "  ${DIM}Tag:        ${IMAGE_TAG}${RESET}"
if [[ -n "$OUTPUT_DIR" ]]; then
    echo -e "  ${DIM}Output:     ${OUTPUT_DIR}${RESET}"
fi
if [[ ${#BUILD_ARGS[@]} -gt 0 ]]; then
    echo -e "  ${DIM}Build args: ${BUILD_ARGS[*]}${RESET}"
fi

if [[ ! -f "$DOCKERFILE" ]]; then
    echo -e "\n  ${RED}✗ Dockerfile not found: ${DOCKERFILE}${RESET}"
    exit 1
fi

if [[ ! -d "$BUILD_CONTEXT" ]]; then
    echo -e "\n  ${RED}✗ Build context not found: ${BUILD_CONTEXT}${RESET}"
    exit 1
fi

if ! command -v docker &>/dev/null; then
    echo -e "\n  ${RED}✗ docker not found in PATH${RESET}"
    exit 1
fi

# ── Build ────────────────────────────────────────────────────────────────────
banner "Building image: ${IMAGE_TAG}"

START_TIME=$SECONDS

DOCKER_ARGS=("build" "-f" "$DOCKERFILE" "-t" "$IMAGE_TAG")
if $NO_CACHE; then DOCKER_ARGS+=("--no-cache"); fi
if [[ ${#BUILD_ARGS[@]} -gt 0 ]]; then DOCKER_ARGS+=("${BUILD_ARGS[@]}"); fi
DOCKER_ARGS+=("$BUILD_CONTEXT")

set +e
docker "${DOCKER_ARGS[@]}" 2>&1 | sed 's/^/     /'
BUILD_RC=${PIPESTATUS[0]}
set -e

ELAPSED=$(( SECONDS - START_TIME ))

if [[ $BUILD_RC -ne 0 ]]; then
    echo -e "\n  ${RED}✗ Build FAILED (exit ${BUILD_RC}) — ${ELAPSED}s${RESET}"
    exit $BUILD_RC
fi

echo -e "\n  ${GREEN}✓ Build succeeded — ${ELAPSED}s${RESET}"

# ── Image info ───────────────────────────────────────────────────────────────
echo -e "\n  ${WHITE}Image details:${RESET}"
docker image inspect "$IMAGE_TAG" --format '  Size: {{.Size}} bytes
  Created: {{.Created}}
  Architecture: {{.Architecture}}
  OS: {{.Os}}' 2>/dev/null | sed "s/^/  ${DIM}/" | sed "s/$/${RESET}/"

# ── Save artifact ───────────────────────────────────────────────────────────
if [[ -n "$OUTPUT_DIR" ]]; then
    banner "Saving image artifact"
    mkdir -p "$OUTPUT_DIR"

    TARBALL="${OUTPUT_DIR}/${IMAGE_TAG//[:\/]/_}.tar"
    echo -e "  ${WHITE}▶  Saving to ${TARBALL}${RESET}"

    set +e
    docker save "$IMAGE_TAG" -o "$TARBALL" 2>&1 | sed 's/^/     /'
    SAVE_RC=${PIPESTATUS[0]}
    set -e

    if [[ $SAVE_RC -ne 0 ]]; then
        echo -e "  ${RED}✗ Failed to save image${RESET}"
        exit $SAVE_RC
    fi

    TARBALL_SIZE=$(du -h "$TARBALL" | cut -f1)
    echo -e "  ${GREEN}✓ Saved (${TARBALL_SIZE})${RESET}"

    # Write metadata for downstream stages
    cat > "${OUTPUT_DIR}/build-metadata.json" <<EOF
{
    "image_tag": "${IMAGE_TAG}",
    "tarball": "${TARBALL}",
    "build_context": "${BUILD_CONTEXT}",
    "dockerfile": "${DOCKERFILE}",
    "build_time_seconds": ${ELAPSED},
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    echo -e "  ${GREEN}✓ Metadata written to ${OUTPUT_DIR}/build-metadata.json${RESET}"
fi

banner "Stage 1 Complete"
