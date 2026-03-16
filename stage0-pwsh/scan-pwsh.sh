#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# scan-pwsh.sh — Stage 0 PowerShell: PSScriptAnalyzer linting
# ─────────────────────────────────────────────────────────────────────────────
# Scans PowerShell scripts using PSScriptAnalyzer via pwsh.
#
# Tools: PSScriptAnalyzer (via pwsh)
#
# Usage:
#   ./scan-pwsh.sh [options]
#
# Options:
#   -p, --path <dir>    Root path to scan (default: .)
#   -S, --strict        Include informational severity
#   -s, --skip <tools>  Skip psscriptanalyzer
#   -h, --help          Show this help
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

if [[ -t 1 ]]; then
    RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m'
    CYAN='\033[0;36m' DIM='\033[2m' WHITE='\033[1;37m' RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' DIM='' WHITE='' RESET=''
fi

SCAN_PATH="."
STRICT=false
SKIP=""
EXIT_CODE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--path)   SCAN_PATH="$2"; shift 2 ;;
        -S|--strict) STRICT=true; shift ;;
        -s|--skip)   SKIP="$2"; shift 2 ;;
        -h|--help)   sed -n '2,/^# ──/{ /^# ──/d; s/^# \?//p; }' "$0"; exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

banner() { local l; l=$(printf '─%.0s' {1..60}); echo -e "\n${CYAN}${l}${RESET}"; echo -e "  ${CYAN}$1${RESET}"; echo -e "${CYAN}${l}${RESET}"; }

START_TIME=$SECONDS
echo -e "\n${CYAN}🔍 scan-pwsh.sh${RESET}"
echo -e "   ${DIM}Path: ${SCAN_PATH} | Strict: ${STRICT}${RESET}"

# ── Check skip ───────────────────────────────────────────────────────────────
if [[ "${SKIP,,}" == *"psscriptanalyzer"* ]]; then
    echo -e "  ${YELLOW}⏭  PSScriptAnalyzer skipped by user${RESET}"
    exit 0
fi

# ── Find PowerShell files ────────────────────────────────────────────────────
banner "Scanning for PowerShell files"
PS_FILES=()
while IFS= read -r -d '' f; do
    PS_FILES+=("$f")
done < <(find "$SCAN_PATH" -type f \( -name "*.ps1" -o -name "*.psm1" -o -name "*.psd1" \) -print0 2>/dev/null)

if [[ ${#PS_FILES[@]} -eq 0 ]]; then
    echo -e "  ${YELLOW}⚠  No PowerShell files found${RESET}"
    exit 0
fi

echo -e "  ${GREEN}✓  PowerShell — ${#PS_FILES[@]} file(s)${RESET}"

# ── Validate pwsh ────────────────────────────────────────────────────────────
if ! command -v pwsh &>/dev/null; then
    echo -e "  ${RED}✗ pwsh not found in PATH${RESET}"
    exit 1
fi

# ── Run PSScriptAnalyzer ─────────────────────────────────────────────────────
banner "PowerShell (${#PS_FILES[@]} files)"

severity="Warning"
if $STRICT; then severity="Information"; fi

file_list=$(printf "'%s'," "${PS_FILES[@]}")
file_list="@(${file_list%,})"

ps_script="
    if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -SkipPublisherCheck
    }
    Import-Module PSScriptAnalyzer
    \$files = ${file_list}
    \$allIssues = @()
    foreach (\$f in \$files) {
        \$allIssues += @(Invoke-ScriptAnalyzer -Path \$f -Severity @('Error','${severity}') -ErrorAction SilentlyContinue)
    }
    if (\$allIssues.Count -gt 0) {
        \$allIssues | Format-Table -Property Severity, RuleName, ScriptName, Line, Message -AutoSize
        exit 1
    }
    exit 0
"

echo -e "  ${WHITE}▶  Running PSScriptAnalyzer...${RESET}"
rc=0
set +e
pwsh -NoProfile -NonInteractive -Command "$ps_script" 2>&1 | sed 's/^/     /'
rc=${PIPESTATUS[0]}
set -e

# ── Summary ──────────────────────────────────────────────────────────────────
ELAPSED=$(( SECONDS - START_TIME ))
banner "Summary"

if [[ $rc -ne 0 ]]; then
    printf "  %-20s %-12s %-14s %s\n" "Tool" "Language" "Status" "Detail"
    printf "  %-20s %-12s %-14s %s\n" "----" "--------" "------" "------"
    printf "  %-20s %-12s %-14s %s\n" "PSScriptAnalyzer" "PowerShell" "Fail" "Exit code: ${rc}"
    echo -e "\n  ${WHITE}Passed: 0 | Failed: 1 | Skipped: 0 | Not Installed: 0${RESET}"
    echo -e "  ${DIM}Elapsed: ${ELAPSED}s${RESET}"
    echo -e "\n  ${RED}✗ FAILED${RESET}"
    exit 1
else
    printf "  %-20s %-12s %-14s %s\n" "Tool" "Language" "Status" "Detail"
    printf "  %-20s %-12s %-14s %s\n" "----" "--------" "------" "------"
    printf "  %-20s %-12s %-14s %s\n" "PSScriptAnalyzer" "PowerShell" "Pass" ""
    echo -e "\n  ${WHITE}Passed: 1 | Failed: 0 | Skipped: 0 | Not Installed: 0${RESET}"
    echo -e "  ${DIM}Elapsed: ${ELAPSED}s${RESET}"
    echo -e "\n  ${GREEN}✓ PASSED${RESET}"
    exit 0
fi
