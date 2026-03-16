#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# comply.sh — Stage 10: Compliance & Policy Enforcement
# ─────────────────────────────────────────────────────────────────────────────
# Evaluates pipeline artifacts against OPA/Conftest policies.
# Verifies image signatures, checks vulnerability reports against thresholds,
# and validates SBOM completeness.
#
# Usage:
#   ./comply.sh [options]
#
# Options:
#   -i, --image <tag>         Image to verify signature (optional)
#   -a, --artifacts <dir>     Artifacts directory from previous stages
#   -p, --policy <dir>        Policy directory (default: ./policies)
#   -o, --output <dir>        Output directory for compliance reports
#   --skip-verify             Skip image signature verification
#   -h, --help                Show this help message
#
# Examples:
#   ./comply.sh --artifacts ./artifacts --policy ./policies
#   ./comply.sh --image jfrog.io/repo/myapp:1.0.0 --artifacts ./artifacts
#   ./comply.sh --artifacts ./artifacts --skip-verify
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
ARTIFACTS_DIR=""
POLICY_DIR="./policies"
OUTPUT_DIR=""
SKIP_VERIFY=false
EXIT_CODE=0
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_SKIPPED=0

# ── Argument Parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--image)       IMAGE="$2"; shift 2 ;;
        -a|--artifacts)   ARTIFACTS_DIR="$2"; shift 2 ;;
        -p|--policy)      POLICY_DIR="$2"; shift 2 ;;
        -o|--output)      OUTPUT_DIR="$2"; shift 2 ;;
        --skip-verify)    SKIP_VERIFY=true; shift ;;
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

check_pass() {
    echo -e "  ${GREEN}✓ PASS: $1${RESET}"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
}

check_fail() {
    echo -e "  ${RED}✗ FAIL: $1${RESET}"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    EXIT_CODE=1
}

check_skip() {
    echo -e "  ${YELLOW}⏭  SKIP: $1${RESET}"
    CHECKS_SKIPPED=$((CHECKS_SKIPPED + 1))
}

# ── Validation ───────────────────────────────────────────────────────────────
banner "Stage 10: Compliance & Policy Enforcement"

if [[ -z "$ARTIFACTS_DIR" ]]; then
    echo -e "  ${RED}✗ --artifacts is required${RESET}"
    exit 1
fi

echo -e "  ${DIM}Artifacts:    ${ARTIFACTS_DIR}${RESET}"
echo -e "  ${DIM}Policies:     ${POLICY_DIR}${RESET}"
echo -e "  ${DIM}Skip verify:  ${SKIP_VERIFY}${RESET}"
if [[ -n "$IMAGE" ]]; then
    echo -e "  ${DIM}Image:        ${IMAGE}${RESET}"
fi

START_TIME=$SECONDS

if [[ -n "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
fi

# ── Check 1: Image Signature Verification ────────────────────────────────────
verify_signature() {
    banner "Signature Verification"

    if $SKIP_VERIFY; then
        check_skip "Image signature verification (--skip-verify)"
        return
    fi

    if [[ -z "$IMAGE" ]]; then
        # Try to get image from stage9 metadata
        if [[ -f "${ARTIFACTS_DIR}/stage9/sbom-metadata.json" ]]; then
            IMAGE=$(jq -r '.target_image // empty' "${ARTIFACTS_DIR}/stage9/sbom-metadata.json")
        fi
    fi

    if [[ -z "$IMAGE" ]]; then
        check_skip "Image signature verification (no image specified)"
        return
    fi

    if ! command -v cosign &>/dev/null; then
        check_skip "Image signature verification (cosign not installed)"
        return
    fi

    echo -e "  ${WHITE}▶  Verifying signature for ${IMAGE}${RESET}"

    set +e
    cosign verify "$IMAGE" --output text 2>&1 | sed 's/^/     /'
    VERIFY_RC=${PIPESTATUS[0]}
    set -e

    if [[ $VERIFY_RC -eq 0 ]]; then
        check_pass "Image signature verified"
    else
        check_fail "Image signature verification failed"
    fi
}

# ── Check 2: Vulnerability Threshold ─────────────────────────────────────────
check_vulnerabilities() {
    banner "Vulnerability Compliance"

    local vuln_report="${ARTIFACTS_DIR}/stage3/vuln-report.json"

    if [[ ! -f "$vuln_report" ]]; then
        check_skip "Vulnerability check (no vuln-report.json found)"
        return
    fi

    echo -e "  ${WHITE}▶  Analyzing ${vuln_report}${RESET}"

    # Count vulnerabilities by severity
    local critical high medium low
    critical=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' "$vuln_report" 2>/dev/null || echo "0")
    high=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH")] | length' "$vuln_report" 2>/dev/null || echo "0")
    medium=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "MEDIUM")] | length' "$vuln_report" 2>/dev/null || echo "0")
    low=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "LOW")] | length' "$vuln_report" 2>/dev/null || echo "0")

    echo -e "     ${DIM}Critical: ${critical}${RESET}"
    echo -e "     ${DIM}High:     ${high}${RESET}"
    echo -e "     ${DIM}Medium:   ${medium}${RESET}"
    echo -e "     ${DIM}Low:      ${low}${RESET}"

    # Policy: No critical vulnerabilities allowed
    if [[ "$critical" -gt 0 ]]; then
        check_fail "Critical vulnerabilities found: ${critical}"
    else
        check_pass "No critical vulnerabilities"
    fi

    # Policy: High vulnerabilities threshold (configurable via policy)
    local high_threshold=10
    if [[ "$high" -gt "$high_threshold" ]]; then
        check_fail "High vulnerabilities exceed threshold: ${high} > ${high_threshold}"
    else
        check_pass "High vulnerabilities within threshold: ${high} <= ${high_threshold}"
    fi
}

# ── Check 3: SBOM Completeness ───────────────────────────────────────────────
check_sbom() {
    banner "SBOM Compliance"

    local sbom_file=""
    for f in "${ARTIFACTS_DIR}/stage9/sbom.cyclonedx.json" "${ARTIFACTS_DIR}/stage9/sbom.spdx.json"; do
        if [[ -f "$f" ]]; then
            sbom_file="$f"
            break
        fi
    done

    if [[ -z "$sbom_file" ]]; then
        check_fail "SBOM not found in artifacts"
        return
    fi

    echo -e "  ${WHITE}▶  Validating ${sbom_file}${RESET}"

    # Check SBOM is valid JSON
    if ! jq empty "$sbom_file" 2>/dev/null; then
        check_fail "SBOM is not valid JSON"
        return
    fi
    check_pass "SBOM is valid JSON"

    # Check SBOM has components
    local component_count
    component_count=$(jq '.components | length' "$sbom_file" 2>/dev/null || echo "0")

    if [[ "$component_count" -eq 0 ]]; then
        check_fail "SBOM has no components"
    else
        check_pass "SBOM contains ${component_count} components"
    fi

    # Check SBOM has metadata
    if jq -e '.metadata' "$sbom_file" &>/dev/null; then
        check_pass "SBOM has metadata"
    else
        check_fail "SBOM missing metadata"
    fi
}

# ── Check 4: Conftest Policy Evaluation ──────────────────────────────────────
run_conftest() {
    banner "Policy Evaluation (Conftest)"

    if ! command -v conftest &>/dev/null; then
        check_skip "Conftest policy evaluation (conftest not installed)"
        return
    fi

    if [[ ! -d "$POLICY_DIR" ]]; then
        check_skip "Conftest policy evaluation (policy directory not found: ${POLICY_DIR})"
        return
    fi

    local policy_count
    policy_count=$(find "$POLICY_DIR" -name "*.rego" 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$policy_count" -eq 0 ]]; then
        check_skip "Conftest policy evaluation (no .rego policies found)"
        return
    fi

    echo -e "  ${WHITE}▶  Running ${policy_count} policies${RESET}"

    # Run conftest against all JSON artifacts
    local conftest_failed=false
    for artifact in "${ARTIFACTS_DIR}"/*/*.json; do
        if [[ -f "$artifact" ]]; then
            echo -e "     ${DIM}Checking: ${artifact}${RESET}"
            set +e
            conftest test "$artifact" --policy "$POLICY_DIR" 2>&1 | sed 's/^/       /'
            if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
                conftest_failed=true
            fi
            set -e
        fi
    done

    if $conftest_failed; then
        check_fail "Conftest policy violations found"
    else
        check_pass "All Conftest policies passed"
    fi
}

# ── Run all checks ───────────────────────────────────────────────────────────
verify_signature
check_vulnerabilities
check_sbom
run_conftest

# ── Write compliance report ──────────────────────────────────────────────────
ELAPSED=$(( SECONDS - START_TIME ))

if [[ -n "$OUTPUT_DIR" ]]; then
    cat > "${OUTPUT_DIR}/compliance-report.json" <<EOF
{
    "image": "${IMAGE}",
    "artifacts_dir": "${ARTIFACTS_DIR}",
    "policy_dir": "${POLICY_DIR}",
    "checks_passed": ${CHECKS_PASSED},
    "checks_failed": ${CHECKS_FAILED},
    "checks_skipped": ${CHECKS_SKIPPED},
    "compliant": $([ $EXIT_CODE -eq 0 ] && echo "true" || echo "false"),
    "elapsed_seconds": ${ELAPSED},
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    echo -e "\n  ${GREEN}✓ Report: ${OUTPUT_DIR}/compliance-report.json${RESET}"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
banner "Stage 10 Complete"

echo -e "  ${WHITE}Passed: ${CHECKS_PASSED} | Failed: ${CHECKS_FAILED} | Skipped: ${CHECKS_SKIPPED}${RESET}"
echo -e "  ${DIM}Elapsed: ${ELAPSED}s${RESET}"

if [[ $EXIT_CODE -ne 0 ]]; then
    echo -e "\n  ${RED}✗ COMPLIANCE FAILED${RESET}"
else
    echo -e "\n  ${GREEN}✓ COMPLIANT${RESET}"
fi

exit $EXIT_CODE
