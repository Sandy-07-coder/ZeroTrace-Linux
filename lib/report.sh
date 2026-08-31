#!/usr/bin/env bash
# lib/report.sh
# Summary formatting and human-readable output.
# Sourced by zerotrace.sh — do not execute directly.

# ---------------------------------------------------------------------------
# Colour helpers (disabled automatically if not a terminal)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'
    C_RED='\033[0;31m'
    C_CYAN='\033[0;36m'
    C_BLUE='\033[0;34m'
    C_MAGENTA='\033[0;35m'
else
    C_RESET='' C_BOLD='' C_GREEN='' C_YELLOW='' C_RED=''
    C_CYAN='' C_BLUE='' C_MAGENTA=''
fi

# ---------------------------------------------------------------------------
# Logging helpers — called from anywhere in the script
# ---------------------------------------------------------------------------
log_verbose() {
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "${C_CYAN}${*}${C_RESET}"
    fi
}

log_warn() {
    echo -e "${C_YELLOW}[WARN] ${*}${C_RESET}" >&2
}

log_error() {
    echo -e "${C_RED}[ERROR] ${*}${C_RESET}" >&2
}

log_info() {
    echo -e "${C_BOLD}${*}${C_RESET}"
}

# ---------------------------------------------------------------------------
# human_bytes <bytes>
# Converts a raw byte count to a human-readable string.
# ---------------------------------------------------------------------------
human_bytes() {
    local raw="${1:-0}"
    # Strip any residual whitespace/newlines from callers
    local bytes="${raw//[$'\t\r\n ']/}"
    bytes="${bytes:-0}"
    if (( bytes == 0 )); then
        echo "0 B"
    elif (( bytes < 1024 )); then
        echo "${bytes} B"
    elif (( bytes < 1048576 )); then
        printf "%.1f KiB\n" "$(echo "scale=1; ${bytes}/1024" | bc 2>/dev/null || echo 0)"
    elif (( bytes < 1073741824 )); then
        printf "%.1f MiB\n" "$(echo "scale=1; ${bytes}/1048576" | bc 2>/dev/null || echo 0)"
    else
        printf "%.2f GiB\n" "$(echo "scale=2; ${bytes}/1073741824" | bc 2>/dev/null || echo 0)"
    fi
}

# ---------------------------------------------------------------------------
# print_separator
# ---------------------------------------------------------------------------
print_separator() {
    local char="${1:--}"
    local width="${2:-60}"
    printf '%*s\n' "${width}" '' | tr ' ' "${char}"
}

# ---------------------------------------------------------------------------
# print_report
# Renders the final human-readable summary to stdout.
# ---------------------------------------------------------------------------
print_report() {
    local run_mode="LIVE RUN"
    [[ "${DRY_RUN}" == "true" ]] && run_mode="DRY RUN"

    echo ""
    print_separator "=" 64
    echo -e "${C_BOLD}${C_MAGENTA}  ZeroTrace — Sanitization Report  [${run_mode}]${C_RESET}"
    print_separator "=" 64

    # ── Cleaned categories ──────────────────────────────────────────────────
    echo -e "\n${C_BOLD}${C_BLUE}── Cleaned Items ──────────────────────────────────────────${C_RESET}"

    local any_cleaned=false
    local category
    for category in "${!REPORT_CLEANED[@]}"; do
        local count="${REPORT_CLEANED[${category}]:-0}"
        local bytes="${REPORT_CLEANED_BYTES[${category}]:-0}"
        if (( count > 0 || bytes > 0 )); then
            any_cleaned=true
            printf "  %-20s  %4d item(s)   %s\n" \
                "${category}" "${count}" "$(human_bytes "${bytes}")"
        fi
    done

    # Dry-run "would clean" list
    if [[ "${DRY_RUN}" == "true" && ${#REPORT_WOULD_CLEAN[@]} -gt 0 ]]; then
        any_cleaned=true
        echo -e "\n  ${C_CYAN}Would clean:${C_RESET}"
        local entry
        for entry in "${REPORT_WOULD_CLEAN[@]}"; do
            echo "    • ${entry}"
        done
    fi

    if ! ${any_cleaned}; then
        echo -e "  ${C_GREEN}✓ Nothing to clean — already clean.${C_RESET}"
    fi


    # ── Process terminations ────────────────────────────────────────────────
    if [[ ${#REPORT_TERMINATIONS[@]} -gt 0 ]]; then
        echo -e "\n${C_BOLD}${C_BLUE}── Process Terminations ────────────────────────────────────${C_RESET}"
        local action
        for action in "${REPORT_TERMINATIONS[@]}"; do
            echo "  • ${action}"
        done
    fi

    # ── Skipped (non-existent) ──────────────────────────────────────────────
    if [[ ${#REPORT_NONEXISTENT[@]} -gt 0 ]]; then
        echo -e "\n${C_BOLD}${C_BLUE}── Skipped (not found) ─────────────────────────────────────${C_RESET}"
        local path
        for path in "${REPORT_NONEXISTENT[@]}"; do
            echo -e "  ${C_YELLOW}• ${path}${C_RESET}"
        done
    fi

    # ── Skipped (protected process) ─────────────────────────────────────────
    if [[ ${#REPORT_SKIPPED_PROTECTED[@]} -gt 0 ]]; then
        echo -e "\n${C_BOLD}${C_BLUE}── Skipped — Protected Process Lock ────────────────────────${C_RESET}"
        local entry
        for entry in "${REPORT_SKIPPED_PROTECTED[@]}"; do
            echo -e "  ${C_YELLOW}• ${entry}${C_RESET}"
        done
    fi

    # ── Failed items ────────────────────────────────────────────────────────
    if [[ ${#REPORT_FAILED[@]} -gt 0 ]]; then
        echo -e "\n${C_BOLD}${C_BLUE}── Failed Items ────────────────────────────────────────────${C_RESET}"
        local entry
        for entry in "${REPORT_FAILED[@]}"; do
            echo -e "  ${C_RED}✗ ${entry}${C_RESET}"
        done
    fi

    # ── Footer ──────────────────────────────────────────────────────────────
    print_separator "-" 64
    if [[ ${#REPORT_FAILED[@]} -eq 0 && ${#REPORT_SKIPPED_PROTECTED[@]} -eq 0 ]]; then
        echo -e "  ${C_GREEN}${C_BOLD}✓ Run completed successfully.${C_RESET}"
    else
        echo -e "  ${C_YELLOW}${C_BOLD}⚠  Run completed with warnings — see above.${C_RESET}"
    fi
    print_separator "=" 64
    echo ""
}
