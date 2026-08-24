#!/usr/bin/env bash
# lib/lockcheck.sh
# lsof-based process-lock detection and SIGTERM/SIGKILL escalation logic.
# Sourced by zerotrace.sh — do not execute directly.

# ---------------------------------------------------------------------------
# Protected processes — NEVER send signals to these under any circumstances.
# ---------------------------------------------------------------------------
declare -a PROTECTED_PROCESSES=(
    "systemd"
    "Xorg"
    "gnome-shell"
    "plasmashell"
    "NetworkManager"
    "sshd"
    "init"
)

# Maximum seconds to wait for a process to exit after SIGTERM
SIGTERM_WAIT_SECS=5

# ---------------------------------------------------------------------------
# is_protected_process <process_name>
# Returns 0 (true) if the process name is on the denylist.
# ---------------------------------------------------------------------------
is_protected_process() {
    local pname="${1}"
    local protected
    for protected in "${PROTECTED_PROCESSES[@]}"; do
        if [[ "${pname}" == "${protected}" ]]; then
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# get_file_holders <path>
# Echoes "PID PROCESSNAME" pairs (one per line) for any processes holding
# the given path open. Returns silently if lsof is not installed.
# ---------------------------------------------------------------------------
get_file_holders() {
    local target_path="${1}"

    if ! command -v lsof &>/dev/null; then
        log_warn "lsof not available — cannot check file locks for: ${target_path}"
        return 0
    fi

    # lsof -F outputs field-formatted data: p=PID, c=Command
    # We use -t to get just PIDs, then map back to names via /proc
    lsof -F pc "${target_path}" 2>/dev/null \
        | awk '
            /^p/ { pid = substr($0,2) }
            /^c/ { cmd = substr($0,2); print pid " " cmd }
        '
}

# ---------------------------------------------------------------------------
# wait_for_exit <pid> <max_seconds>
# Polls until <pid> exits or the timeout is reached.
# Returns 0 if the process exited, 1 if still running.
# ---------------------------------------------------------------------------
wait_for_exit() {
    local pid="${1}"
    local max_secs="${2}"
    local elapsed=0

    while kill -0 "${pid}" 2>/dev/null; do
        sleep 1
        (( elapsed++ ))
        if (( elapsed >= max_secs )); then
            return 1
        fi
    done
    return 0
}

# ---------------------------------------------------------------------------
# release_file_lock <path>
# Finds any process holding <path> open and escalates:
#   1. Skip if protected.
#   2. SIGTERM → wait up to SIGTERM_WAIT_SECS.
#   3. SIGKILL if still alive.
# Returns 0 if the file is now free (or was never locked).
# Returns 1 if the lock could not be released (protected process).
# ---------------------------------------------------------------------------
release_file_lock() {
    local target_path="${1}"
    local holders
    local all_freed=true

    holders=$(get_file_holders "${target_path}")

    if [[ -z "${holders}" ]]; then
        return 0  # No lock
    fi

    local pid pname
    while IFS=' ' read -r pid pname; do
        [[ -z "${pid}" ]] && continue

        if is_protected_process "${pname}"; then
            log_warn "Skipped lock release — protected process: PID=${pid} NAME=${pname} FILE=${target_path}"
            REPORT_SKIPPED_PROTECTED+=("${target_path} (held by protected: ${pname}/${pid})")
            all_freed=false
            continue
        fi

        # Attempt graceful termination
        log_verbose "Sending SIGTERM to PID=${pid} (${pname}) holding: ${target_path}"
        kill -SIGTERM "${pid}" 2>/dev/null || true

        if wait_for_exit "${pid}" "${SIGTERM_WAIT_SECS}"; then
            log_verbose "PID=${pid} (${pname}) exited gracefully after SIGTERM."
            REPORT_TERMINATIONS+=("SIGTERM pid=${pid} name=${pname} file=${target_path} result=graceful")
        else
            # Escalate to SIGKILL
            log_verbose "SIGTERM timed out — sending SIGKILL to PID=${pid} (${pname})."
            kill -SIGKILL "${pid}" 2>/dev/null || true
            REPORT_TERMINATIONS+=("SIGKILL pid=${pid} name=${pname} file=${target_path} result=forced")
            # Brief pause to allow kernel to reap
            sleep 0.5
        fi
    done <<< "${holders}"

    ${all_freed} && return 0 || return 1
}
