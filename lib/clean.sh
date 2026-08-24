#!/usr/bin/env bash
# lib/clean.sh
# Deletion routines: rm wrappers for temp dirs, shred wrappers for sensitive files.
# Sourced by zerotrace.sh — do not execute directly.

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Fallback for when shred is unavailable: overwrite with zeros then delete
_overwrite_then_delete() {
    local target="${1}"
    local size
    size=$(stat -c%s "${target}" 2>/dev/null || echo 0)

    # Overwrite with zeros
    if dd if=/dev/zero of="${target}" bs=1 count="${size}" conv=notrunc &>/dev/null; then
        rm -f "${target}"
        log_verbose "  [overwrite+delete] ${target}"
        return 0
    else
        log_warn "  Failed to overwrite: ${target}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# shred_file <path>
# Securely deletes a regular file. Uses shred if available, falls back to
# overwrite-with-zeros + delete. Logs the result.
# ---------------------------------------------------------------------------
shred_file() {
    local target="${1}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_verbose "  [dry-run] would shred: ${target}"
        return 0
    fi

    # Safety: only operate on regular files
    if [[ ! -f "${target}" ]]; then
        return 0
    fi

    # Attempt to release any process lock first
    if ! release_file_lock "${target}"; then
        # Protected process holds the file — skip it
        REPORT_FAILED+=("${target} (protected-process lock)")
        return 1
    fi

    local file_size
    file_size=$(stat -c%s "${target}" 2>/dev/null || echo 0)

    if command -v shred &>/dev/null; then
        if shred -u "${target}" 2>/dev/null; then
            log_verbose "  [shred] ${target} (${file_size} bytes)"
            return 0
        else
            log_warn "  shred failed on: ${target} — falling back to overwrite+delete"
            _overwrite_then_delete "${target}"
        fi
    else
        _overwrite_then_delete "${target}"
    fi
}

# ---------------------------------------------------------------------------
# clean_rmrf_target <dir>
# Removes the *contents* of a directory (not the directory itself) using
# rm -rf. Safe to call on /tmp and /var/tmp.
# ---------------------------------------------------------------------------
clean_rmrf_target() {
    local target_dir="${1}"
    local category="${2:-rmrf}"

    if [[ ! -d "${target_dir}" ]]; then
        log_verbose "  [skip — does not exist] ${target_dir}"
        REPORT_NONEXISTENT+=("${target_dir}")
        return 0
    fi

    # Collect size before cleaning for the report
    local size_before count_before
    size_before=$(du -sb "${target_dir}" 2>/dev/null | awk '{print $1}' || echo 0)
    size_before="${size_before//[$'\t\r\n ']/}"
    count_before=$(find "${target_dir}" -mindepth 1 2>/dev/null | wc -l || echo 0)
    count_before="${count_before//[$'\t\r\n ']/}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_verbose "  [dry-run] would rm -rf contents of: ${target_dir} (${count_before} items, $(human_bytes "${size_before}"))"
        REPORT_WOULD_CLEAN+=("${category}: ${target_dir} — ${count_before} items, $(human_bytes "${size_before}")")
        return 0
    fi

    # Delete contents but preserve the directory itself.
    # Skip items not owned by the current user (e.g. systemd-private-* dirs,
    # .X11-unix, .ICE-unix — these are system infrastructure, not session data).
    local item item_uid errors current_uid
    errors=0
    current_uid=$(id -u)
    while IFS= read -r item; do
        [[ -z "${item}" ]] && continue

        # Check ownership — skip silently if owned by another user
        item_uid=$(stat -c%u "${item}" 2>/dev/null) || item_uid=-1
        if [[ "${item_uid}" != "${current_uid}" ]]; then
            log_verbose "  [skip — not owned by us] ${item}"
            continue
        fi

        if rm -rf "${item}" 2>/dev/null; then
            log_verbose "  [rm -rf] ${item}"
        else
            log_warn "  Could not remove: ${item}"
            REPORT_FAILED+=("${item} (rm failed)")
            errors=$(( errors + 1 ))
        fi
    done < <(find "${target_dir}" -mindepth 1 -maxdepth 1 2>/dev/null)

    local size_after count_after
    size_after=$(du -sb "${target_dir}" 2>/dev/null | awk '{print $1}' || echo 0)
    size_after="${size_after//[$'\t\r\n ']/}"
    count_after=$(find "${target_dir}" -mindepth 1 2>/dev/null | wc -l || echo 0)
    count_after="${count_after//[$'\t\r\n ']/}"

    local cleaned_count cleaned_size
    cleaned_count=$(( count_before - count_after ))
    cleaned_size=$(( size_before - size_after ))

    REPORT_CLEANED["${category}"]=$(( ${REPORT_CLEANED["${category}"]:-0} + cleaned_count ))
    REPORT_CLEANED_BYTES["${category}"]=$(( ${REPORT_CLEANED_BYTES["${category}"]:-0} + cleaned_size ))

    if (( count_after == 0 )); then
        log_verbose "  ${target_dir}: clean (${cleaned_count} items removed, ${cleaned_size} bytes freed)"
    else
        log_verbose "  ${target_dir}: ${count_after} item(s) remain (${errors} removal error(s))"
    fi
}

# ---------------------------------------------------------------------------
# clean_shred_directory <dir> <category>
# Recursively shreds all regular files under <dir>.
# Preserves directory structure (does not rm the directories themselves).
# ---------------------------------------------------------------------------
clean_shred_directory() {
    local target_dir="${1}"
    local category="${2:-cache}"

    if [[ ! -d "${target_dir}" ]]; then
        log_verbose "  [skip — does not exist] ${target_dir}"
        REPORT_NONEXISTENT+=("${target_dir}")
        return 0
    fi

    local count_before size_before
    count_before=$(find "${target_dir}" -type f 2>/dev/null | wc -l || echo 0)
    count_before="${count_before//[$'\t\r\n ']/}"
    size_before=$(du -sb "${target_dir}" 2>/dev/null | awk '{print $1}' || echo 0)
    size_before="${size_before//[$'\t\r\n ']/}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_verbose "  [dry-run] would shred all files in: ${target_dir} (${count_before} files, $(human_bytes "${size_before}"))"
        REPORT_WOULD_CLEAN+=("${category}: ${target_dir} — ${count_before} files, $(human_bytes "${size_before}")")
        return 0
    fi

    local file cleaned=0 failed=0
    while IFS= read -r file; do
        [[ -z "${file}" ]] && continue
        if shred_file "${file}"; then
            (( cleaned++ )) || true
        else
            (( failed++ )) || true
        fi
    done < <(find "${target_dir}" -type f 2>/dev/null)

    # Remove empty directories left behind
    find "${target_dir}" -mindepth 1 -type d -empty -delete 2>/dev/null || true

    REPORT_CLEANED["${category}"]=$(( ${REPORT_CLEANED["${category}"]:-0} + cleaned ))
    local size_after
    size_after=$(du -sb "${target_dir}" 2>/dev/null | awk '{print $1}' || echo 0)
    size_after="${size_after//[$'\t\r\n ']/}"
    local freed=$(( size_before - size_after ))
    REPORT_CLEANED_BYTES["${category}"]=$(( ${REPORT_CLEANED_BYTES["${category}"]:-0} + freed ))

    log_verbose "  ${target_dir}: shredded ${cleaned} file(s), ${freed} bytes freed (${failed} failed)"
}

# ---------------------------------------------------------------------------
# clean_shred_file_list <category> <path1> [path2 ...]
# Shreds a specific list of file paths. Used for browser-specific targets.
# ---------------------------------------------------------------------------
clean_shred_file_list() {
    local category="${1}"
    shift
    local file cleaned=0 failed=0 total_freed=0

    for file in "$@"; do
        if [[ ! -f "${file}" ]]; then
            log_verbose "  [skip — does not exist] ${file}"
            continue
        fi

        local fsize
        fsize=$(stat -c%s "${file}" 2>/dev/null || echo 0)

        if [[ "${DRY_RUN}" == "true" ]]; then
            log_verbose "  [dry-run] would shred: ${file}"
            REPORT_WOULD_CLEAN+=("${category}: ${file} (${fsize} bytes)")
            continue
        fi

        if shred_file "${file}"; then
            (( cleaned++ )) || true
            (( total_freed += fsize )) || true
        else
            (( failed++ )) || true
        fi
    done

    if [[ "${DRY_RUN}" != "true" ]]; then
        REPORT_CLEANED["${category}"]=$(( ${REPORT_CLEANED["${category}"]:-0} + cleaned ))
        REPORT_CLEANED_BYTES["${category}"]=$(( ${REPORT_CLEANED_BYTES["${category}"]:-0} + total_freed ))
    fi
}
