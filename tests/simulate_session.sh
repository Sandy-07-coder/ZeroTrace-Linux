#!/usr/bin/env bash
# tests/simulate_session.sh
# Creates realistic session clutter on the current user's account so that
# ZeroTrace has meaningful targets to sanitize.
#
# Usage:
#   ./tests/simulate_session.sh [--quiet]
#
# What it does:
#   1. Writes files to /tmp and /var/tmp
#   2. Creates fake cache entries under ~/.cache
#   3. Simulates Chrome/Chromium artefacts
#   4. Simulates Firefox artefacts
#   5. Optionally launches a real Firefox/Chrome process in the background
#      so the process-lock path can be tested (only if --open-browser is set)
#
# This script is destructive to your HOME cache. Run on a test VM snapshot.

set -euo pipefail
IFS=$'\n\t'

QUIET=false
OPEN_BROWSER=false

for arg in "$@"; do
    case "${arg}" in
        --quiet)        QUIET=true ;;
        --open-browser) OPEN_BROWSER=true ;;
        --help|-h)
            echo "Usage: ./tests/simulate_session.sh [--quiet] [--open-browser]"
            exit 0
            ;;
    esac
done

log() { [[ "${QUIET}" == "false" ]] && echo "[simulate] $*" || true; }

# ---------------------------------------------------------------------------
# 1. /tmp clutter
# ---------------------------------------------------------------------------
log "Creating /tmp clutter..."
mkdir -p /tmp/zerotrace_test
for i in {1..5}; do
    dd if=/dev/urandom of="/tmp/zerotrace_test/dummy_file_${i}.bin" bs=1024 count=64 2>/dev/null
done
echo "session=abc123; user=testuser" > /tmp/zerotrace_test/session_leak.txt
cp /etc/hostname /tmp/zerotrace_test/hostname_copy.txt 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2. /var/tmp clutter
# ---------------------------------------------------------------------------
log "Creating /var/tmp clutter..."
mkdir -p /var/tmp/zerotrace_test
dd if=/dev/urandom of="/var/tmp/zerotrace_test/var_dummy.bin" bs=1024 count=128 2>/dev/null

# ---------------------------------------------------------------------------
# 3. ~/.cache fake entries
# ---------------------------------------------------------------------------
log "Populating ~/.cache with fake entries..."

# Generic app cache
mkdir -p "${HOME}/.cache/zerotrace_fake_app"
dd if=/dev/urandom of="${HOME}/.cache/zerotrace_fake_app/data.bin" bs=1024 count=32 2>/dev/null

# Thumbnail-style cache
mkdir -p "${HOME}/.cache/thumbnails/normal"
dd if=/dev/urandom of="${HOME}/.cache/thumbnails/normal/abcdef1234567890.png" bs=512 count=2 2>/dev/null

# ---------------------------------------------------------------------------
# 4. Chrome/Chromium artefacts
# ---------------------------------------------------------------------------
log "Simulating Chrome artefacts..."

for chrome_base in \
    "${HOME}/.config/google-chrome/Default" \
    "${HOME}/.config/chromium/Default"
do
    mkdir -p "${chrome_base}"
    for fname in Cookies "Cookies-journal" "Web Data" "Web Data-journal" History; do
        echo "fake_data_for_${fname}=LEAK$(date +%s)" > "${chrome_base}/${fname}"
        # WAL sidecar
        echo "wal_data" > "${chrome_base}/${fname}-wal"
        echo "shm_data" > "${chrome_base}/${fname}-shm"
    done
done

# ---------------------------------------------------------------------------
# 5. Firefox artefacts
# ---------------------------------------------------------------------------
log "Simulating Firefox artefacts..."

FF_BASE="${HOME}/.mozilla/firefox"
FF_PROFILE="${FF_BASE}/zerotrace.test-profile.default-release"
mkdir -p "${FF_PROFILE}"

# Write a minimal profiles.ini so target discovery works
cat > "${FF_BASE}/profiles.ini" <<EOF
[Profile0]
Name=default-release
IsRelative=1
Path=zerotrace.test-profile.default-release
Default=1
EOF

for fname in cookies.sqlite formhistory.sqlite places.sqlite; do
    echo "fake_sqlite_data_for_${fname}" > "${FF_PROFILE}/${fname}"
    echo "wal_data" > "${FF_PROFILE}/${fname}-wal"
    echo "shm_data" > "${FF_PROFILE}/${fname}-shm"
done

# ---------------------------------------------------------------------------
# 6. (Optional) Open a browser so process-lock code path is exercised
# ---------------------------------------------------------------------------
if [[ "${OPEN_BROWSER}" == "true" ]]; then
    if command -v firefox &>/dev/null; then
        log "Launching Firefox in the background (for lock testing)..."
        firefox --headless &>/dev/null &
        BROWSER_PID=$!
        log "Firefox PID: ${BROWSER_PID} — run zerotrace.sh while it is running."
    elif command -v google-chrome &>/dev/null; then
        log "Launching Chrome in the background (for lock testing)..."
        google-chrome --headless --disable-gpu &>/dev/null &
        BROWSER_PID=$!
        log "Chrome PID: ${BROWSER_PID} — run zerotrace.sh while it is running."
    else
        log "No browser found for --open-browser test."
    fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
if [[ "${QUIET}" == "false" ]]; then
    echo ""
    echo "=========================================="
    echo "  Session simulation complete!"
    echo ""
    echo "  Created clutter in:"
    echo "    /tmp/zerotrace_test/"
    echo "    /var/tmp/zerotrace_test/"
    echo "    ~/.cache/zerotrace_fake_app/"
    echo "    ~/.cache/thumbnails/normal/"
    echo "    ~/.config/google-chrome/Default/"
    echo "    ~/.config/chromium/Default/"
    echo "    ~/.mozilla/firefox/*.default-release/"
    echo ""
    echo "  Now run:  ./zerotrace.sh --verbose"
    echo "=========================================="
fi
