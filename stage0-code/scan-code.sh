#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scan-code.sh — Stage 0 Code: Code quality & general security
# ─────────────────────────────────────────────────────────────────────────────
# Scans Python, Dockerfile, Shell scripts for lint/security issues.
# Also runs gitleaks for secrets detection.
#
# Tools: ruff, bandit, hadolint, shellcheck, gitleaks
#
# Usage:
#   ./scan-code.sh [options]
#
# Options:
#   -p, --path <dir>    Root path to scan (default: .)
#   -f, --fix           Apply auto-fixes (ruff)
#   -s, --skip <tools>  Comma-separated tools to skip
#   -S, --strict        Treat warnings as errors
#   -h, --help          Show this help
#
# Valid skip values: ruff, bandit, hadolint, shellcheck, gitleaks
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
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

# ── Argument Parsing ─────────────────────────────────────────────────────────
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
    local output_file; output_file=$(mktemp)
    local rc=0; set +e; "$cmd" "${args[@]}" > "$output_file" 2>&1; rc=$?; set -e
    cat "$output_file" | sed 's/^/     /'
    if [[ $rc -ne 0 ]]; then
        echo -e "  ${RED}✗  ${tool_name} failed (exit ${rc})${RESET}"
        echo -e "  ${RED}--- ${tool_name} output ---${RESET}"
        cat "$output_file" | sed 's/^/     /'
        echo -e "  ${RED}--- end ${tool_name} output ---${RESET}"
        add_result "$tool_name" "$language" "Fail" "Exit code: ${rc}"
    else
        add_result "$tool_name" "$language" "Pass"; echo -e "  ${GREEN}✓  ${tool_name} passed${RESET}"
    fi
    rm -f "$output_file"
}
find_files() {
    local base="$1"; shift; local patterns=("$@") results=()
    for p in "${patterns[@]}"; do while IFS= read -r -d '' f; do results+=("$f"); done < <(find "$base" -type f -name "$p" -print0 2>/dev/null); done
    if [[ ${#results[@]} -gt 0 ]]; then printf '%s\0' "${results[@]}" | sort -uz | tr '\0' '\n'; fi
}

# ── Scan & Lint ──────────────────────────────────────────────────────────────
START_TIME=$SECONDS
echo -e "\n${CYAN}🔍 scan-code.sh${RESET}"
echo -e "   ${DIM}Path: ${SCAN_PATH} | Fix: ${FIX} | Strict: ${STRICT}${RESET}"

banner "Scanning for code files"
mapfile -t PYTHON_FILES < <(find_files "$SCAN_PATH" "*.py")
mapfile -t DOCKER_FILES < <(find_files "$SCAN_PATH" "Dockerfile" "Dockerfile.*" "*.dockerfile")
mapfile -t SHELL_FILES  < <(find_files "$SCAN_PATH" "*.sh" "*.bash" "*.zsh" "*.ksh")

for lbl in "Python:${#PYTHON_FILES[@]}" "Dockerfile:${#DOCKER_FILES[@]}" "Shell:${#SHELL_FILES[@]}"; do
    name="${lbl%%:*}"; cnt="${lbl##*:}"
    if [[ $cnt -gt 0 ]]; then echo -e "  ${GREEN}✓  ${name} — ${cnt} file(s)${RESET}"; fi
done

# ── Python ───────────────────────────────────────────────────────────────────
if [[ ${#PYTHON_FILES[@]} -gt 0 ]]; then
    banner "Python (${#PYTHON_FILES[@]} files)"
    local_ruff_args=("check" "$SCAN_PATH" "--output-format" "concise")
    if $FIX; then local_ruff_args+=("--fix"); fi
    run_tool "ruff" "Python" "ruff" "${local_ruff_args[@]}"

    if $FIX; then run_tool "ruff-format" "Python" "ruff" format "$SCAN_PATH"
    else run_tool "ruff-format" "Python" "ruff" format --check --diff "$SCAN_PATH"; fi

    run_tool "bandit" "Python" "bandit" -r "$SCAN_PATH" -f custom --severity-level medium -q
fi

# ── Dockerfile ───────────────────────────────────────────────────────────────
if [[ ${#DOCKER_FILES[@]} -gt 0 ]]; then
    banner "Dockerfile (${#DOCKER_FILES[@]} files)"
    for file in "${DOCKER_FILES[@]}"; do
        echo -e "  ${DIM}📄 ${file}${RESET}"
        local_args=("$file")
        if $STRICT; then local_args+=("--failure-threshold" "warning"); fi
        run_tool "hadolint" "Dockerfile" "hadolint" "${local_args[@]}"
    done
fi

# ── Shell ────────────────────────────────────────────────────────────────────
if [[ ${#SHELL_FILES[@]} -gt 0 ]]; then
    banner "Shell Scripts (${#SHELL_FILES[@]} files)"
    supported=("sh" "bash" "dash" "ksh")
    for file in "${SHELL_FILES[@]}"; do
        echo -e "  ${DIM}📄 ${file}${RESET}"
        shell=""
        first_line=$(head -n1 "$file" 2>/dev/null || true)
        if [[ "$first_line" =~ ^#!.*/(bash|zsh|dash|ksh|fish|sh)[[:space:]] ]] || [[ "$first_line" =~ ^#!.*/(bash|zsh|dash|ksh|fish|sh)$ ]]; then
            shell="${BASH_REMATCH[1]}"
        else shell="${file##*.}"; fi

        is_sup=false; for s in "${supported[@]}"; do if [[ "$shell" == "$s" ]]; then is_sup=true; break; fi; done
        if [[ -n "$shell" ]] && ! $is_sup; then
            echo -e "     ${YELLOW}Skipping — shellcheck does not support '${shell}'${RESET}"
            add_result "shellcheck" "Shell" "Skipped" "Unsupported: ${shell}"; continue
        fi
        local_args=("--format" "gcc" "$file")
        if $STRICT; then local_args=("--severity" "style" "--format" "gcc" "$file"); fi
        run_tool "shellcheck" "Shell" "shellcheck" "${local_args[@]}"
    done
fi

# ── Secrets ──────────────────────────────────────────────────────────────────
banner "Secrets Scan"
gitleaks_args=("detect" "--source" "$SCAN_PATH" "--no-git" "--verbose")
if $STRICT; then gitleaks_args+=("--exit-code" "1"); fi
run_tool "gitleaks" "Secrets" "gitleaks" "${gitleaks_args[@]}"

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
