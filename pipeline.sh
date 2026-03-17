#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# pipeline.sh — Run pipeline stages locally via Docker
# ─────────────────────────────────────────────────────────────────────────────
# Orchestrates all or individual pipeline stages against a target repo.
# Each stage runs in its own container with the repo mounted at /workspace.
#
# Usage:
#   ./pipeline.sh [options] [-- stage-specific-args]
#
# Options:
#   -T, --target <path|url>   Local path or git URL to scan (default: current directory)
#   -s, --stage <stages>      Comma-separated stages to run (default: all)
#                              Valid: 0-code, 0-iac, 0-pwsh, 1, 3, 9, 10, all
#   -t, --tag <tag>           Image tag for stage 1 build (default: app:latest)
#   -p, --prefix <prefix>    Image name prefix (e.g. shiftleft -> shiftleft/stage0-code)
#   -R, --registry <url>      Container registry for images (e.g. jfrog.io/docker-local)
#   -o, --output <dir>        Artifacts directory (default: ./artifacts)
#   --fix                     Pass --fix to stage 0 scripts
#   --strict                  Pass --strict to all stages
#   --fail-on <severity>      Pass --fail-on to stage 3 (e.g. CRITICAL)
#   --skip-sign               Skip signing in stage 9
#   --keyless                 Use keyless signing in stage 9
#   -k, --key <path>          Cosign key for stage 9
#   --skip-verify             Skip signature verification in stage 10
#   --dry-run                 Show what would run without executing
#   -h, --help                Show this help message
#
# Examples:
#   ./pipeline.sh                                              # Run all stages on cwd
#   ./pipeline.sh --target ~/projects/myapp --stage 0-code     # Scan a local dir
#   ./pipeline.sh --target https://github.com/org/repo.git     # Scan a git repo
#   ./pipeline.sh --target git@github.com:org/repo.git         # SSH git URL
#   ./pipeline.sh --stage 0-code,0-iac --fix                   # Stage 0 with auto-fix
#   ./pipeline.sh --stage 1,3,9 --tag myapp:1.0.0 --skip-sign # Build + scan + SBOM
#   ./pipeline.sh --registry jfrog.io/docker-local --keyless   # Full pipeline with push
#   ./pipeline.sh --prefix shiftleft --stage 0-code           # Use shiftleft/stage0-code image
#   ./pipeline.sh --dry-run                                    # Preview what would run
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
TARGET=""
STAGES="all"
IMAGE_TAG="app:latest"
IMAGE_PREFIX=""
REGISTRY=""
ARTIFACTS="./artifacts"
FIX=false
STRICT=false
FAIL_ON=""
SKIP_SIGN=false
KEYLESS=false
COSIGN_KEY=""
SKIP_VERIFY=false
DRY_RUN=false
CLONED_DIR=""

# ── Argument Parsing ─────────────────────────────────────────────────────────
EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -T|--target)       TARGET="$2"; shift 2 ;;
        -s|--stage)        STAGES="$2"; shift 2 ;;
        -t|--tag)          IMAGE_TAG="$2"; shift 2 ;;
        -p|--prefix)       IMAGE_PREFIX="$2"; shift 2 ;;
        -R|--registry)     REGISTRY="$2"; shift 2 ;;
        -o|--output)       ARTIFACTS="$2"; shift 2 ;;
        --fix)             FIX=true; shift ;;
        --strict)          STRICT=true; shift ;;
        --fail-on)         FAIL_ON="$2"; shift 2 ;;
        --skip-sign)       SKIP_SIGN=true; shift ;;
        --keyless)         KEYLESS=true; shift ;;
        -k|--key)          COSIGN_KEY="$2"; shift 2 ;;
        --skip-verify)     SKIP_VERIFY=true; shift ;;
        --dry-run)         DRY_RUN=true; shift ;;
        -h|--help)
            sed -n '2,/^# ──/{ /^# ──/d; s/^# \?//p; }' "$0"
            exit 0
            ;;
        --)                shift; EXTRA_ARGS=("$@"); break ;;
        *)                 EXTRA_ARGS+=("$1"); shift ;;
    esac
done

# Resolve target: git URL or local path
resolve_target() {
    if [[ -z "$TARGET" ]]; then
        REPO_PATH="$(pwd)"
        return
    fi

    # Detect git URLs (https://, git@, ssh://, git://)
    if [[ "$TARGET" =~ ^(https?://|git@|ssh://|git://) ]]; then
        CLONED_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pipeline-XXXXXX")
        echo -e "  ${WHITE}▶  Cloning ${TARGET}${RESET}"
        echo -e "  ${DIM}   → ${CLONED_DIR}${RESET}"
        if ! git clone --depth 1 "$TARGET" "$CLONED_DIR" 2>&1 | sed 's/^/     /'; then
            echo -e "  ${RED}✗ Git clone failed${RESET}"
            exit 1
        fi
        REPO_PATH="$CLONED_DIR"
        echo -e "  ${GREEN}✓ Cloned${RESET}"
    else
        REPO_PATH="$(cd "$TARGET" && pwd)"
    fi
}

# Cleanup cloned repo on exit
cleanup() {
    if [[ -n "$CLONED_DIR" ]] && [[ -d "$CLONED_DIR" ]]; then
        echo -e "\n  ${DIM}Cleaning up cloned repo: ${CLONED_DIR}${RESET}"
        rm -rf "$CLONED_DIR"
    fi
}
trap cleanup EXIT

resolve_target
mkdir -p "$ARTIFACTS"
ARTIFACTS="$(cd "$ARTIFACTS" && pwd)"

# ── Helpers ──────────────────────────────────────────────────────────────────
banner() {
    local line
    line=$(printf '═%.0s' {1..60})
    echo -e "\n${CYAN}${line}${RESET}"
    echo -e "  ${WHITE}$1${RESET}"
    echo -e "${CYAN}${line}${RESET}"
}

should_run() {
    local stage="$1"
    [[ "$STAGES" == "all" ]] && return 0
    IFS=',' read -ra stage_list <<< "$STAGES"
    for s in "${stage_list[@]}"; do
        [[ "$(echo "$s" | tr -d ' ')" == "$stage" ]] && return 0
    done
    return 1
}

# Build proxy env flags for docker run
PROXY_ENV=()
for var in HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy; do
    if [[ -n "${!var:-}" ]]; then
        PROXY_ENV+=(-e "${var}=${!var}")
    fi
done
if [[ ${#PROXY_ENV[@]} -gt 0 ]]; then
    echo -e "  ${DIM}Proxy:     forwarding ${#PROXY_ENV[@]} env vars into containers${RESET}"
fi

# Resolve stage image name — use registry prefix if set
stage_image() {
    local name="$1"
    if [[ -n "$IMAGE_PREFIX" ]]; then
        name="${IMAGE_PREFIX}/${name}"
    fi
    if [[ -n "$REGISTRY" ]]; then
        echo "${REGISTRY}/${name}"
    else
        echo "$name"
    fi
}

run_docker() {
    local name="$1"; shift
    local args=("$@")
    if $DRY_RUN; then
        echo -e "  ${DIM}[dry-run] docker run --rm ${args[*]}${RESET}"
        return 0
    fi
    echo -e "  ${WHITE}▶  ${name}${RESET}"
    set +e
    docker run --rm "${args[@]}" 2>&1 | sed 's/^/  /'
    local rc=${PIPESTATUS[0]}
    set -e
    return $rc
}

STAGE_RESULTS=()
record_stage() {
    local stage="$1" rc="$2"
    if [[ $rc -eq 0 ]]; then
        STAGE_RESULTS+=("${stage}:PASS")
        echo -e "\n  ${GREEN}✓ ${stage} PASSED${RESET}"
    else
        STAGE_RESULTS+=("${stage}:FAIL")
        echo -e "\n  ${RED}✗ ${stage} FAILED${RESET}"
    fi
}

# ── Pipeline Start ───────────────────────────────────────────────────────────
PIPELINE_START=$SECONDS
EXIT_CODE=0

banner "Pipeline"
echo -e "  ${DIM}Target:    ${TARGET:-$(pwd)}${RESET}"
echo -e "  ${DIM}Repo:      ${REPO_PATH}${RESET}"
echo -e "  ${DIM}Stages:    ${STAGES}${RESET}"
echo -e "  ${DIM}Tag:       ${IMAGE_TAG}${RESET}"
if [[ -n "$IMAGE_PREFIX" ]]; then echo -e "  ${DIM}Prefix:    ${IMAGE_PREFIX}${RESET}"; fi
echo -e "  ${DIM}Artifacts: ${ARTIFACTS}${RESET}"
if [[ -n "$REGISTRY" ]]; then echo -e "  ${DIM}Registry:  ${REGISTRY}${RESET}"; fi
if $DRY_RUN; then echo -e "  ${YELLOW}DRY RUN — no containers will execute${RESET}"; fi

# ── Stage 0: Code ────────────────────────────────────────────────────────────
if should_run "0-code"; then
    banner "Stage 0: Code Quality & Security"
    s0_args=("${PROXY_ENV[@]+"${PROXY_ENV[@]}"}" -v "${REPO_PATH}":/workspace "$(stage_image stage0-code)" --path /workspace)
    if $FIX; then s0_args+=(--fix); fi
    if $STRICT; then s0_args+=(--strict); fi
    s0_args+=("${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}")
    rc=0; run_docker "stage0-code" "${s0_args[@]}" || rc=$?
    record_stage "stage0-code" $rc
    if [[ $rc -ne 0 ]]; then EXIT_CODE=1; fi
fi

# ── Stage 0: IaC ─────────────────────────────────────────────────────────────
if should_run "0-iac"; then
    banner "Stage 0: IaC Linting & Compliance"
    s0_args=("${PROXY_ENV[@]+"${PROXY_ENV[@]}"}" -v "${REPO_PATH}":/workspace "$(stage_image stage0-iac)" --path /workspace)
    if $FIX; then s0_args+=(--fix); fi
    if $STRICT; then s0_args+=(--strict); fi
    s0_args+=("${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}")
    rc=0; run_docker "stage0-iac" "${s0_args[@]}" || rc=$?
    record_stage "stage0-iac" $rc
    if [[ $rc -ne 0 ]]; then EXIT_CODE=1; fi
fi

# ── Stage 0: PowerShell ──────────────────────────────────────────────────────
if should_run "0-pwsh"; then
    banner "Stage 0: PowerShell Linting"
    s0_args=("${PROXY_ENV[@]+"${PROXY_ENV[@]}"}" -v "${REPO_PATH}":/workspace "$(stage_image stage0-pwsh)" --path /workspace)
    if $STRICT; then s0_args+=(--strict); fi
    s0_args+=("${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}")
    rc=0; run_docker "stage0-pwsh" "${s0_args[@]}" || rc=$?
    record_stage "stage0-pwsh" $rc
    if [[ $rc -ne 0 ]]; then EXIT_CODE=1; fi
fi

# ── Stage 1: Build ───────────────────────────────────────────────────────────
if should_run "1"; then
    banner "Stage 1: Build"
    mkdir -p "${ARTIFACTS}/stage1"
    s1_args=(
        "${PROXY_ENV[@]+"${PROXY_ENV[@]}"}"
        -v /var/run/docker.sock:/var/run/docker.sock
        -v "${REPO_PATH}":/workspace
        -v "${ARTIFACTS}":/artifacts
        "$(stage_image stage1-build)"
        --context /workspace --tag "$IMAGE_TAG" --output /artifacts/stage1
    )
    s1_args+=("${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}")
    rc=0; run_docker "stage1-build" "${s1_args[@]}" || rc=$?
    record_stage "stage1-build" $rc
    if [[ $rc -ne 0 ]]; then EXIT_CODE=1; fi
fi

# ── Stage 3: SCA ─────────────────────────────────────────────────────────────
if should_run "3"; then
    banner "Stage 3: Software Composition Analysis"
    mkdir -p "${ARTIFACTS}/stage3"
    s3_args=(
        "${PROXY_ENV[@]+"${PROXY_ENV[@]}"}"
        -v /var/run/docker.sock:/var/run/docker.sock
        -v "${REPO_PATH}":/workspace
        -v "${ARTIFACTS}":/artifacts
        "$(stage_image stage3-sca)"
        --image "$IMAGE_TAG" --output /artifacts/stage3
    )
    if [[ -n "$FAIL_ON" ]]; then s3_args+=(--fail-on "$FAIL_ON"); fi
    s3_args+=("${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}")
    rc=0; run_docker "stage3-sca" "${s3_args[@]}" || rc=$?
    record_stage "stage3-sca" $rc
    if [[ $rc -ne 0 ]]; then EXIT_CODE=1; fi
fi

# ── Stage 9: SBOM & Sign ─────────────────────────────────────────────────────
if should_run "9"; then
    banner "Stage 9: SBOM & Signing"
    mkdir -p "${ARTIFACTS}/stage9"
    s9_args=(
        "${PROXY_ENV[@]+"${PROXY_ENV[@]}"}"
        -v /var/run/docker.sock:/var/run/docker.sock
        -v "${ARTIFACTS}":/artifacts
    )
    # Mount secrets file if present
    if [[ -f "${REPO_PATH}/.secrets" ]]; then
        s9_args+=(-v "${REPO_PATH}/.secrets":/workspace/.secrets:ro)
    fi
    # Mount cosign key if specified
    if [[ -n "$COSIGN_KEY" ]]; then
        s9_args+=(-v "$(cd "$(dirname "$COSIGN_KEY")" && pwd)/$(basename "$COSIGN_KEY")":/cosign.key:ro)
    fi
    s9_args+=($(stage_image stage9-sbom) --image "$IMAGE_TAG" --output /artifacts/stage9)
    if [[ -n "$REGISTRY" ]]; then s9_args+=(--registry "$REGISTRY"); fi
    if $SKIP_SIGN; then s9_args+=(--skip-sign); fi
    if $KEYLESS; then s9_args+=(--keyless); fi
    if [[ -n "$COSIGN_KEY" ]]; then s9_args+=(--key /cosign.key); fi
    s9_args+=("${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}")
    rc=0; run_docker "stage9-sbom" "${s9_args[@]}" || rc=$?
    record_stage "stage9-sbom" $rc
    if [[ $rc -ne 0 ]]; then EXIT_CODE=1; fi
fi

# ── Stage 10: Compliance ─────────────────────────────────────────────────────
if should_run "10"; then
    banner "Stage 10: Compliance & Policy"
    mkdir -p "${ARTIFACTS}/stage10"
    s10_args=(
        "${PROXY_ENV[@]+"${PROXY_ENV[@]}"}"
        -v /var/run/docker.sock:/var/run/docker.sock
        -v "${ARTIFACTS}":/artifacts
    )
    # Mount policies if they exist
    if [[ -d "${REPO_PATH}/policies" ]]; then
        s10_args+=(-v "${REPO_PATH}/policies":/policies)
    fi
    s10_args+=($(stage_image stage10-compliance) --artifacts /artifacts --output /artifacts/stage10)
    if [[ -n "$IMAGE_TAG" ]]; then s10_args+=(--image "$IMAGE_TAG"); fi
    if $SKIP_VERIFY; then s10_args+=(--skip-verify); fi
    s10_args+=("${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}")
    rc=0; run_docker "stage10-compliance" "${s10_args[@]}" || rc=$?
    record_stage "stage10-compliance" $rc
    if [[ $rc -ne 0 ]]; then EXIT_CODE=1; fi
fi

# ── Pipeline Summary ─────────────────────────────────────────────────────────
PIPELINE_ELAPSED=$(( SECONDS - PIPELINE_START ))

banner "Pipeline Summary"

printf "  %-25s %s\n" "Stage" "Result"
printf "  %-25s %s\n" "─────" "──────"
for result in "${STAGE_RESULTS[@]}"; do
    stage="${result%%:*}"
    status="${result##*:}"
    if [[ "$status" == "PASS" ]]; then
        printf "  %-25s ${GREEN}%s${RESET}\n" "$stage" "$status"
    else
        printf "  %-25s ${RED}%s${RESET}\n" "$stage" "$status"
    fi
done

passed=0 failed=0
for r in "${STAGE_RESULTS[@]}"; do
    case "${r##*:}" in PASS) passed=$((passed+1));; FAIL) failed=$((failed+1));; esac
done

echo -e "\n  ${WHITE}Passed: ${passed} | Failed: ${failed}${RESET}"
echo -e "  ${DIM}Total elapsed: ${PIPELINE_ELAPSED}s${RESET}"

if [[ $EXIT_CODE -ne 0 ]]; then
    echo -e "\n  ${RED}✗ PIPELINE FAILED${RESET}"
else
    echo -e "\n  ${GREEN}✓ PIPELINE PASSED${RESET}"
fi

exit $EXIT_CODE
