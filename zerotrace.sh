#!/usr/bin/env bash
# zerotrace.sh — ZeroTrace Phase 1: Manual session sanitizer for Ubuntu/Linux
# Usage:
#   ./zerotrace.sh             # Full clean with summary
#   ./zerotrace.sh --dry-run   # Show what would be cleaned, without deleting
#   ./zerotrace.sh --verbose   # Per-file actions + summary
#   ./zerotrace.sh --dry-run --verbose  # Combined
#
# Safety:
#   • Never deletes outside the explicitly listed target paths.
#   • Idempotent — safe to run repeatedly.
#   • Protected system processes are never signalled.

set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# Resolve script directory regardless of invocation path
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# ---------------------------------------------------------------------------
# Parse CLI flags
# ---------------------------------------------------------------------------
DRY_RUN=false
VERBOSE=false

for arg in "$@"; do
    case "${arg}" in
        --dry-run)   DRY_RUN=true  ;;
        --verbose)   VERBOSE=true  ;;
        --help|-h)
            cat <<'EOF'
ZeroTrace — session sanitizer for shared Ubuntu machines (Phase 1)

Usage:
  ./zerotrace.sh [OPTIONS]

Options:
  --dry-run    Show what would be cleaned without making any changes.
  --verbose    Print each individual file action in addition to the summary.
  --help       Show this help message and exit.

Description:
  Cleans /tmp, /var/tmp, Chrome/Chromium session artefacts, and
  Firefox session artefacts.
  Processes holding target files are gracefully terminated (SIGTERM → SIGKILL).
  Protected system processes (systemd, Xorg, etc.) are never signalled.
EOF
            exit 0
            ;;
        *)
            echo "[ERROR] Unknown option: ${arg}" >&2
            echo "Run './zerotrace.sh --help' for usage." >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Source library modules (order matters — report first for log helpers)
# ---------------------------------------------------------------------------
# shellcheck source=lib/report.sh
source "${LIB_DIR}/report.sh"
# shellcheck source=lib/targets.sh
source "${LIB_DIR}/targets.sh"
# shellcheck source=lib/lockcheck.sh
source "${LIB_DIR}/lockcheck.sh"
# shellcheck source=lib/clean.sh
source "${LIB_DIR}/clean.sh"

# ---------------------------------------------------------------------------
# Shared report data structures
# ---------------------------------------------------------------------------
declare -A REPORT_CLEANED=()         # category → count of items cleaned
declare -A REPORT_CLEANED_BYTES=()   # category → bytes freed
declare -a REPORT_NONEXISTENT=()     # paths that didn't exist (skipped, not errors)
declare -a REPORT_FAILED=()          # paths that couldn't be cleaned + reason
declare -a REPORT_SKIPPED_PROTECTED=() # paths skipped due to protected-process lock
declare -a REPORT_TERMINATIONS=()    # log of every signal sent
declare -a REPORT_WOULD_CLEAN=()     # dry-run "would clean" entries
DNS_FLUSH_RESULT=""

# ---------------------------------------------------------------------------
# Trap for unexpected exits
# ---------------------------------------------------------------------------
trap 'log_error "ZeroTrace interrupted. Partial report:"; print_report' ERR INT TERM

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
log_info ""
log_info "  ZeroTrace — Session Sanitizer (Phase 1)"
if [[ "${DRY_RUN}" == "true" ]]; then
    echo -e "  ${C_YELLOW}Mode: DRY RUN — no files will be modified.${C_RESET}"
fi
if [[ "${VERBOSE}" == "true" ]]; then
    echo -e "  ${C_CYAN}Verbosity: ON${C_RESET}"
fi
log_info ""

# ===========================================================================
# STEP 1: Clean /tmp and /var/tmp (rm -rf contents)
# ===========================================================================
log_info "▶ Cleaning /tmp ..."
clean_rmrf_target "/tmp" "tmp"

log_info "▶ Cleaning /var/tmp ..."
clean_rmrf_target "/var/tmp" "var_tmp"


# ===========================================================================
# STEP 3: Chrome / Chromium browser artefacts
# ===========================================================================
log_info "▶ Scanning for Chrome/Chromium session artefacts ..."

mapfile -t chrome_files < <(get_chrome_targets)

if [[ ${#chrome_files[@]} -eq 0 ]]; then
    log_verbose "  No Chrome/Chromium files found — skipping."
    REPORT_NONEXISTENT+=("Chrome/Chromium profile artefacts (none found)")
else
    log_verbose "  Found ${#chrome_files[@]} Chrome/Chromium file(s)."
    clean_shred_file_list "chrome" "${chrome_files[@]}"
fi

# ===========================================================================
# STEP 4: Firefox browser artefacts
# ===========================================================================
log_info "▶ Scanning for Firefox session artefacts ..."

mapfile -t firefox_files < <(get_firefox_targets)

if [[ ${#firefox_files[@]} -eq 0 ]]; then
    log_verbose "  No Firefox files found — skipping."
    REPORT_NONEXISTENT+=("Firefox profile artefacts (none found)")
else
    log_verbose "  Found ${#firefox_files[@]} Firefox file(s) across $(discover_firefox_profiles | wc -l) profile(s)."
    clean_shred_file_list "firefox" "${firefox_files[@]}"
fi


# ===========================================================================
# Final report
# ===========================================================================
# Remove the trap now that we're printing the report intentionally
trap - ERR INT TERM

print_report
