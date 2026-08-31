#!/usr/bin/env bash
# lib/targets.sh
# Target path definitions and discovery (e.g., Firefox profile lookup)
# Sourced by zerotrace.sh — do not execute directly.

# ---------------------------------------------------------------------------
# Static target categories
# ---------------------------------------------------------------------------

# Simple rm-rf targets (contents only, directories are preserved)
declare -a RMRF_TARGETS=(
    "/tmp"
    "/var/tmp"
)



# Chrome/Chromium specific files (relative to profile dir)
declare -a CHROME_SENSITIVE_FILES=(
    "Cookies"
    "Cookies-journal"
    "Web Data"
    "Web Data-journal"
    "History"
    "History-journal"
)

# Chrome/Chromium profile base dirs
declare -a CHROME_PROFILE_BASES=(
    "${HOME}/.config/google-chrome/Default"
    "${HOME}/.config/chromium/Default"
)

# Firefox sensitive files (relative to profile dir)
declare -a FIREFOX_SENSITIVE_FILES=(
    "cookies.sqlite"
    "cookies.sqlite-wal"
    "cookies.sqlite-shm"
    "formhistory.sqlite"
    "formhistory.sqlite-wal"
    "formhistory.sqlite-shm"
    "places.sqlite"
    "places.sqlite-wal"
    "places.sqlite-shm"
)

# ---------------------------------------------------------------------------
# discover_firefox_profiles()
# Outputs the absolute paths to all discovered Firefox profile directories,
# one per line.
# ---------------------------------------------------------------------------
discover_firefox_profiles() {
    local ff_base="${HOME}/.mozilla/firefox"

    if [[ ! -d "${ff_base}" ]]; then
        return 0  # Firefox not installed — silent
    fi

    # profiles.ini lists [Profile<N>] sections with Path= lines
    local ini="${ff_base}/profiles.ini"
    if [[ -f "${ini}" ]]; then
        while IFS= read -r line; do
            # Strip leading/trailing whitespace
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            if [[ "${line}" =~ ^Path=(.+)$ ]]; then
                local rel_path="${BASH_REMATCH[1]}"
                # Path can be relative or absolute
                if [[ "${rel_path}" == /* ]]; then
                    echo "${rel_path}"
                else
                    echo "${ff_base}/${rel_path}"
                fi
            fi
        done < "${ini}"
    else
        # Fallback: glob for any *.default* directories
        local profile_dir
        for profile_dir in "${ff_base}"/*.default* "${ff_base}"/*.default-release; do
            [[ -d "${profile_dir}" ]] && echo "${profile_dir}"
        done
    fi
}

# ---------------------------------------------------------------------------
# get_chrome_targets()
# Echoes (to stdout) all Chrome/Chromium sensitive file paths that exist,
# plus their -wal and -shm siblings.
# ---------------------------------------------------------------------------
get_chrome_targets() {
    local base_dir sensitive_file target_path sibling
    for base_dir in "${CHROME_PROFILE_BASES[@]}"; do
        [[ ! -d "${base_dir}" ]] && continue
        for sensitive_file in "${CHROME_SENSITIVE_FILES[@]}"; do
            target_path="${base_dir}/${sensitive_file}"
            # Primary file
            [[ -f "${target_path}" ]] && echo "${target_path}"
            # WAL / SHM siblings (skip if already in the list)
            for sibling in "${target_path}-wal" "${target_path}-shm"; do
                [[ -f "${sibling}" ]] && echo "${sibling}"
            done
        done
    done
}

# ---------------------------------------------------------------------------
# get_firefox_targets()
# Echoes (to stdout) all Firefox sensitive file paths that exist across
# all discovered profiles.
# ---------------------------------------------------------------------------
get_firefox_targets() {
    local profile_dir sensitive_file target_path
    while IFS= read -r profile_dir; do
        [[ ! -d "${profile_dir}" ]] && continue
        for sensitive_file in "${FIREFOX_SENSITIVE_FILES[@]}"; do
            target_path="${profile_dir}/${sensitive_file}"
            [[ -f "${target_path}" ]] && echo "${target_path}"
        done
    done < <(discover_firefox_profiles)
}
