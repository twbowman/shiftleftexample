#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scan.sh — Stage 3: Software Composition Analysis (SCA)
# ─────────────────────────────────────────────────────────────────────────────
# Scans container images or filesystems for vulnerabilities using Trivy.
# Can load images from Stage 1 tarballs or scan directly from registry.
#
# Usage:
#   ./scan.sh [options]
#
# Options:
#   -i, --image <tag>         Image to scan (tag or tarball path)
#   -r, --repo <path>         Git repo or filesystem path to scan
#   -o, --output <dir>        Output directory for reports
#   -s, --severity <levels>   Severity levels (default: HIGH,CRITICAL)
#   --fail-on <severity>      Exit non-zero if vulnerabilities found at this level
#   --ignore-unfixed          Ignore vulnerabilities without fixes
#   -h, --help                Show this help message
#
# Examples:
#   ./scan.sh --image myapp:1.0.0 --output /artifacts/stage3
#   ./scan.sh --image /artifacts/stage1/myapp_1.0.0.tar --output /artifacts/stage3
#   ./scan.sh --repo /workspace --output /artifacts/stage3
#   ./scan.sh --image myapp:1.0.0 --fail-on CRITICAL
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
REPO_PATH=""
OUTPUT_DIR=""
SEVERITY="HIGH,CRITICAL"
FAIL_ON=""
IGNORE_UNFIXED=false
EXIT_CODE=0

# ── Argument Parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--image)           IMAGE="$2"; shift 2 ;;
        -r|--repo)            REPO_PATH="$2"; shift 2 ;;
        -o|--output)          OUTPUT_DIR="$2"; shift 2 ;;
        -s|--severity)        SEVERITY="$2"; shift 2 ;;
        --fail-on)            FAIL_ON="$2"; shift 2 ;;
        --ignore-unfixed)     IGNORE_UNFIXED=true; shift ;;
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
banner "Stage 3: Software Composition Analysis"

if [[ -z "$IMAGE" ]] && [[ -z "$REPO_PATH" ]]; then
    echo -e "  ${RED}✗ Must specify --image or --repo${RESET}"
    exit 1
fi

if ! command -v trivy &>/dev/null; then
    echo -e "  ${RED}✗ trivy not found in PATH${RESET}"
    exit 1
fi

START_TIME=$SECONDS

# ── Load image from tarball if needed ────────────────────────────────────────
if [[ -n "$IMAGE" ]] && [[ -f "$IMAGE" ]]; then
    banner "Loading image from tarball"
    echo -e "  ${WHITE}▶  Loading ${IMAGE}${RESET}"

    if ! command -v docker &>/dev/null; then
        echo -e "  ${RED}✗ docker required to load tarballs${RESET}"
        exit 1
    fi

    set +e
    LOAD_OUTPUT=$(docker load -i "$IMAGE" 2>&1)
    LOAD_RC=$?
    set -e

    if [[ $LOAD_RC -ne 0 ]]; then
        echo -e "  ${RED}✗ Failed to load image: ${LOAD_OUTPUT}${RESET}"
        exit $LOAD_RC
    fi

    # Extract the loaded image tag
    IMAGE=$(echo "$LOAD_OUTPUT" | grep -oP 'Loaded image: \K.*' || echo "$LOAD_OUTPUT" | grep -oP 'Loaded image ID: \K.*')
    echo -e "  ${GREEN}✓ Loaded: ${IMAGE}${RESET}"
fi

# ── Prepare output directory ─────────────────────────────────────────────────
if [[ -n "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
fi

# ── Image Scan ───────────────────────────────────────────────────────────────
run_image_scan() {
    banner "Scanning image: ${IMAGE}"

    echo -e "  ${DIM}Severity:       ${SEVERITY}${RESET}"
    if [[ -n "$FAIL_ON" ]]; then
        echo -e "  ${DIM}Fail on:        ${FAIL_ON}${RESET}"
    fi
    echo -e "  ${DIM}Ignore unfixed: ${IGNORE_UNFIXED}${RESET}"

    # Table output to console
    local trivy_args=("image" "--severity" "$SEVERITY")
    if $IGNORE_UNFIXED; then trivy_args+=("--ignore-unfixed"); fi
    if [[ -n "$FAIL_ON" ]]; then trivy_args+=("--exit-code" "1" "--severity" "$FAIL_ON"); fi
    trivy_args+=("$IMAGE")

    echo -e "\n  ${WHITE}▶  Vulnerability scan${RESET}"
    set +e
    trivy "${trivy_args[@]}" 2>&1 | sed 's/^/     /'
    local scan_rc=${PIPESTATUS[0]}
    set -e

    if [[ $scan_rc -ne 0 ]] && [[ -n "$FAIL_ON" ]]; then
        echo -e "  ${RED}✗ Vulnerabilities found at ${FAIL_ON} level${RESET}"
        EXIT_CODE=1
    elif [[ $scan_rc -ne 0 ]]; then
        echo -e "  ${YELLOW}⚠  Scan completed with findings${RESET}"
    else
        echo -e "  ${GREEN}✓ No vulnerabilities at ${SEVERITY} level${RESET}"
    fi

    # JSON report for downstream stages
    if [[ -n "$OUTPUT_DIR" ]]; then
        echo -e "\n  ${WHITE}▶  Generating JSON report${RESET}"
        local json_args=("image" "--severity" "$SEVERITY" "--format" "json" "--output" "${OUTPUT_DIR}/vuln-report.json")
        if $IGNORE_UNFIXED; then json_args+=("--ignore-unfixed"); fi
        json_args+=("$IMAGE")

        set +e
        trivy "${json_args[@]}" 2>&1 | sed 's/^/     /'
        set -e

        echo -e "  ${GREEN}✓ Report: ${OUTPUT_DIR}/vuln-report.json${RESET}"
    fi
}

# ── Repo/Filesystem Scan ────────────────────────────────────────────────────
run_repo_scan() {
    banner "Scanning repo: ${REPO_PATH}"

    echo -e "  ${DIM}Severity: ${SEVERITY}${RESET}"

    local trivy_args=("fs" "--severity" "$SEVERITY")
    if $IGNORE_UNFIXED; then trivy_args+=("--ignore-unfixed"); fi
    if [[ -n "$FAIL_ON" ]]; then trivy_args+=("--exit-code" "1" "--severity" "$FAIL_ON"); fi
    trivy_args+=("$REPO_PATH")

    echo -e "\n  ${WHITE}▶  Dependency scan${RESET}"
    set +e
    trivy "${trivy_args[@]}" 2>&1 | sed 's/^/     /'
    local scan_rc=${PIPESTATUS[0]}
    set -e

    if [[ $scan_rc -ne 0 ]] && [[ -n "$FAIL_ON" ]]; then
        echo -e "  ${RED}✗ Vulnerabilities found at ${FAIL_ON} level${RESET}"
        EXIT_CODE=1
    elif [[ $scan_rc -ne 0 ]]; then
        echo -e "  ${YELLOW}⚠  Scan completed with findings${RESET}"
    else
        echo -e "  ${GREEN}✓ No vulnerabilities at ${SEVERITY} level${RESET}"
    fi

    # JSON report
    if [[ -n "$OUTPUT_DIR" ]]; then
        echo -e "\n  ${WHITE}▶  Generating JSON report${RESET}"
        local json_args=("fs" "--severity" "$SEVERITY" "--format" "json" "--output" "${OUTPUT_DIR}/repo-scan.json")
        if $IGNORE_UNFIXED; then json_args+=("--ignore-unfixed"); fi
        json_args+=("$REPO_PATH")

        set +e
        trivy "${json_args[@]}" 2>&1 | sed 's/^/     /'
        set -e

        echo -e "  ${GREEN}✓ Report: ${OUTPUT_DIR}/repo-scan.json${RESET}"
    fi
}

# ── Run scans ────────────────────────────────────────────────────────────────
if [[ -n "$IMAGE" ]]; then run_image_scan; fi
if [[ -n "$REPO_PATH" ]]; then run_repo_scan; fi

# ── Write metadata ───────────────────────────────────────────────────────────
ELAPSED=$(( SECONDS - START_TIME ))

if [[ -n "$OUTPUT_DIR" ]]; then
    cat > "${OUTPUT_DIR}/scan-metadata.json" <<EOF
{
    "image": "${IMAGE}",
    "repo_path": "${REPO_PATH}",
    "severity": "${SEVERITY}",
    "fail_on": "${FAIL_ON}",
    "ignore_unfixed": ${IGNORE_UNFIXED},
    "exit_code": ${EXIT_CODE},
    "scan_time_seconds": ${ELAPSED},
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    echo -e "\n  ${GREEN}✓ Metadata: ${OUTPUT_DIR}/scan-metadata.json${RESET}"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
banner "Stage 3 Complete"
echo -e "  ${DIM}Elapsed: ${ELAPSED}s${RESET}"

if [[ $EXIT_CODE -ne 0 ]]; then
    echo -e "  ${RED}✗ Stage 3 FAILED${RESET}"
else
    echo -e "  ${GREEN}✓ Stage 3 PASSED${RESET}"
fi

exit $EXIT_CODE
