#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scan-iac.sh — Stage 0 IaC: Infrastructure-as-code linting & compliance
# ─────────────────────────────────────────────────────────────────────────────
# Scans Terraform and Ansible for lint/security/compliance issues.
#
# Tools: tflint, checkov, ansible-lint
#
# Usage:
#   ./scan-iac.sh [options]
#
# Options:
#   -p, --path <dir>    Root path to scan (default: .)
#   -f, --fix           Apply auto-fixes (tflint)
#   -s, --skip <tools>  Comma-separated tools to skip
#   -S, --strict        Treat warnings as errors
#   -h, --help          Show this help
#
# Valid skip values: tflint, checkov, ansible-lint
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

if [[ -t 1 ]]; then
    RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m'
    CYAN='\033[0;36m' DIM='\033[2m' WHITE='\033[1;37m' RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' DIM='' WHITE='' RESET=''
fi

SCAN_PATH="."
FIX=false
STRICT=false
SKIP=""
EXIT_CODE=0
RESULT_TOOLS=()
RESULT_LANGS=()
RESULT_STATUSES=()
RESULT_DETAILS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--path)   SCAN_PATH="$2"; shift 2 ;;
        -f|--fix)    FIX=true; shift ;;
        -s|--skip)   SKIP="$2"; shift 2 ;;
        -S|--strict) STRICT=true; shift ;;
        -h|--help)   sed -n '2,/^# ──/{ /^# ──/d; s/^# \?//p; }' "$0"; exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

IFS=',' read -ra SKIP_LIST <<< "$(echo "$SKIP" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"

# ── Helpers ──────────────────────────────────────────────────────────────────
banner() { local l; l=$(printf '─%.0s' {1..60}); echo -e "\n${CYAN}${l}${RESET}"; echo -e "  ${CYAN}$1${RESET}"; echo -e "${CYAN}${l}${RESET}"; }
is_skipped() { local t="${1,,}"; for s in "${SKIP_LIST[@]}"; do [[ "$s" == "$t" ]] && return 0; done; return 1; }
tool_available() { command -v "$1" &>/dev/null; }
add_result() {
    RESULT_TOOLS+=("$1"); RESULT_LANGS+=("$2"); RESULT_STATUSES+=("$3"); RESULT_DETAILS+=("${4:-}")
    if [[ "$3" == "Fail" ]]; then EXIT_CODE=1; fi; return 0
}
run_tool() {
    local tool_name="$1" language="$2" cmd="$3"; shift 3; local args=("$@")
    if is_skipped "$tool_name"; then add_result "$tool_name" "$language" "Skipped"; echo -e "  ${YELLOW}⏭  ${tool_name} skipped${RESET}"; return; fi
    if ! tool_available "$cmd"; then add_result "$tool_name" "$language" "NotInstalled" "'${cmd}' not found"; echo -e "  ${YELLOW}⚠  ${tool_name} not installed${RESET}"; return; fi
    echo -e "  ${WHITE}▶  Running ${tool_name}...${RESET}"
    local rc=0; set +e; "$cmd" "${args[@]}" 2>&1 | sed 's/^/     /'; rc=${PIPESTATUS[0]}; set -e
    if [[ $rc -ne 0 ]]; then add_result "$tool_name" "$language" "Fail" "Exit code: ${rc}"; echo -e "  ${RED}✗  ${tool_name} failed (exit ${rc})${RESET}"
    else add_result "$tool_name" "$language" "Pass"; echo -e "  ${GREEN}✓  ${tool_name} passed${RESET}"; fi
}
find_files() {
    local base="$1"; shift; local patterns=("$@") results=()
    for p in "${patterns[@]}"; do while IFS= read -r -d '' f; do results+=("$f"); done < <(find "$base" -type f -name "$p" -print0 2>/dev/null); done
    if [[ ${#results[@]} -gt 0 ]]; then printf '%s\0' "${results[@]}" | sort -uz | tr '\0' '\n'; fi
}

# ── Scan ─────────────────────────────────────────────────────────────────────
START_TIME=$SECONDS
echo -e "\n${CYAN}🔍 scan-iac.sh${RESET}"
echo -e "   ${DIM}Path: ${SCAN_PATH} | Fix: ${FIX} | Strict: ${STRICT}${RESET}"

banner "Scanning for IaC files"
mapfile -t TF_FILES < <(find_files "$SCAN_PATH" "*.tf" "*.tfvars")

# Ansible heuristic detection
HAS_ANSIBLE=false
for ind in "ansible.cfg" ".ansible-lint" "galaxy.yml" "requirements.yml"; do
    if find "$SCAN_PATH" -type f -name "$ind" -print -quit 2>/dev/null | grep -q .; then HAS_ANSIBLE=true; break; fi
done
if ! $HAS_ANSIBLE; then
    for d in "playbooks" "roles" "inventories" "group_vars" "host_vars" "handlers" "tasks"; do
        if find "$SCAN_PATH" -type d -name "$d" -print -quit 2>/dev/null | grep -q .; then HAS_ANSIBLE=true; break; fi
    done
fi
ANSIBLE_FILES=()
if $HAS_ANSIBLE; then mapfile -t ANSIBLE_FILES < <(find_files "$SCAN_PATH" "*.yml" "*.yaml"); fi

if [[ ${#TF_FILES[@]} -gt 0 ]]; then echo -e "  ${GREEN}✓  Terraform — ${#TF_FILES[@]} file(s)${RESET}"; fi
if [[ ${#ANSIBLE_FILES[@]} -gt 0 ]]; then echo -e "  ${GREEN}✓  Ansible — ${#ANSIBLE_FILES[@]} file(s)${RESET}"; fi

# ── Terraform ────────────────────────────────────────────────────────────────
if [[ ${#TF_FILES[@]} -gt 0 ]]; then
    banner "Terraform (${#TF_FILES[@]} files)"
    mapfile -t tf_dirs < <(printf '%s\n' "${TF_FILES[@]}" | xargs -I{} dirname {} | sort -u)
    for dir in "${tf_dirs[@]}"; do
        echo -e "  ${DIM}📁 ${dir}${RESET}"
        tflint_args=("--chdir" "$dir")
        if $FIX; then tflint_args+=("--fix"); fi
        run_tool "tflint" "Terraform" "tflint" "${tflint_args[@]}"

        checkov_args=("--directory" "$dir" "--framework" "terraform" "--compact" "--quiet")
        if ! $STRICT; then checkov_args+=("--soft-fail"); fi
        run_tool "checkov" "Terraform" "checkov" "${checkov_args[@]}"
    done
fi

# ── Ansible ──────────────────────────────────────────────────────────────────
if [[ ${#ANSIBLE_FILES[@]} -gt 0 ]]; then
    banner "Ansible (${#ANSIBLE_FILES[@]} files)"
    alint_args=("$SCAN_PATH")
    if $STRICT; then alint_args+=("--strict"); fi
    run_tool "ansible-lint" "Ansible" "ansible-lint" "${alint_args[@]}"

    checkov_args=("--directory" "$SCAN_PATH" "--framework" "ansible" "--compact" "--quiet")
    if ! $STRICT; then checkov_args+=("--soft-fail"); fi
    run_tool "checkov" "Ansible" "checkov" "${checkov_args[@]}"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
ELAPSED=$(( SECONDS - START_TIME ))
banner "Summary"
if [[ ${#RESULT_TOOLS[@]} -gt 0 ]]; then
    printf "  %-20s %-12s %-14s %s\n" "Tool" "Language" "Status" "Detail"
    printf "  %-20s %-12s %-14s %s\n" "----" "--------" "------" "------"
    for i in "${!RESULT_TOOLS[@]}"; do
        printf "  %-20s %-12s %-14s %s\n" "${RESULT_TOOLS[$i]}" "${RESULT_LANGS[$i]}" "${RESULT_STATUSES[$i]}" "${RESULT_DETAILS[$i]}"
    done
fi
passed=0 failed=0 skipped=0 missing=0
for st in "${RESULT_STATUSES[@]}"; do
    case "$st" in Pass) passed=$((passed+1));; Fail) failed=$((failed+1));; Skipped) skipped=$((skipped+1));; NotInstalled) missing=$((missing+1));; esac
done
echo -e "\n  ${WHITE}Passed: ${passed} | Failed: ${failed} | Skipped: ${skipped} | Not Installed: ${missing}${RESET}"
echo -e "  ${DIM}Elapsed: ${ELAPSED}s${RESET}"
if [[ $EXIT_CODE -ne 0 ]]; then echo -e "\n  ${RED}✗ FAILED${RESET}"; else echo -e "\n  ${GREEN}✓ PASSED${RESET}"; fi
exit $EXIT_CODE
