#!/usr/bin/env bash
# install.sh — ZeroTrace installer for Ubuntu/Debian systems

set -euo pipefail

APP_NAME="zerotrace"
INSTALL_DIR="$HOME/.local/share/zerotrace"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
AUTOSTART_DIR="$HOME/.config/autostart"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Colors ────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; exit 1; }

echo ""
echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
echo -e "${BOLD}║     ZeroTrace Installer              ║${NC}"
echo -e "${BOLD}║     Session Sanitizer for Linux      ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
echo ""

# ── Check dependencies ────────────────────────────────────────────
echo -e "${BOLD}[1/5] Checking dependencies...${NC}"

missing=()

command -v bash   >/dev/null 2>&1 || missing+=("bash")
command -v python3 >/dev/null 2>&1 || missing+=("python3")
command -v lsof   >/dev/null 2>&1 || missing+=("lsof")
command -v shred  >/dev/null 2>&1 || missing+=("coreutils (shred)")

if python3 -c "import gi; gi.require_version('Gtk', '3.0'); from gi.repository import Gtk" 2>/dev/null; then
    ok "python3-gi (GTK3 bindings) found"
else
    missing+=("python3-gi")
fi

if [ ${#missing[@]} -gt 0 ]; then
    echo ""
    warn "Missing dependencies: ${missing[*]}"
    echo ""
    echo "  Install them with:"
    echo -e "  ${BOLD}sudo apt install ${missing[*]}${NC}"
    echo ""
    read -rp "  Continue anyway? [y/N] " choice
    [[ "$choice" =~ ^[Yy]$ ]] || exit 1
else
    ok "All dependencies found"
fi

# ── Install files ─────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[2/5] Installing files to ${INSTALL_DIR}...${NC}"

mkdir -p "$INSTALL_DIR/lib"
mkdir -p "$INSTALL_DIR/tests"
mkdir -p "$BIN_DIR"

cp "$SOURCE_DIR/zerotrace.sh"          "$INSTALL_DIR/"
cp "$SOURCE_DIR/zerotrace-gui.py"      "$INSTALL_DIR/"
cp "$SOURCE_DIR/zerotrace-listener.py" "$INSTALL_DIR/"
cp "$SOURCE_DIR/lib/"*.sh              "$INSTALL_DIR/lib/"
cp "$SOURCE_DIR/tests/"*.sh            "$INSTALL_DIR/tests/"

chmod +x "$INSTALL_DIR/zerotrace.sh"
chmod +x "$INSTALL_DIR/zerotrace-gui.py"
chmod +x "$INSTALL_DIR/zerotrace-listener.py"

ok "Core files installed"

# ── Create CLI wrapper in PATH ────────────────────────────────────
echo ""
echo -e "${BOLD}[3/5] Creating CLI command...${NC}"

cat > "$BIN_DIR/zerotrace" << 'WRAPPER'
#!/usr/bin/env bash
exec "$HOME/.local/share/zerotrace/zerotrace.sh" "$@"
WRAPPER
chmod +x "$BIN_DIR/zerotrace"

ok "You can now run 'zerotrace' from the terminal"

# ── Install desktop launcher ─────────────────────────────────────
echo ""
echo -e "${BOLD}[4/5] Installing desktop launcher...${NC}"

mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/zerotrace.desktop" << EOF
[Desktop Entry]
Type=Application
Name=ZeroTrace
Comment=Clean session traces on shared machines
Exec=python3 $INSTALL_DIR/zerotrace-gui.py
Icon=security-high
Terminal=false
Categories=Utility;System;
EOF

ok "ZeroTrace added to application menu"

# ── Install autostart for listener ────────────────────────────────
echo ""
echo -e "${BOLD}[5/5] Setting up automatic session listener...${NC}"

mkdir -p "$AUTOSTART_DIR"

cat > "$AUTOSTART_DIR/zerotrace-listener.desktop" << EOF
[Desktop Entry]
Type=Application
Name=ZeroTrace Listener
Comment=Background listener that triggers cleanup on logout or switch-user
Exec=python3 $INSTALL_DIR/zerotrace-listener.py
Hidden=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Phase=Application
NoDisplay=true
EOF

ok "Listener will auto-start on login"

# ── Done ──────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  Installation complete!${NC}"
echo -e "${BOLD}════════════════════════════════════════${NC}"
echo ""
echo "  Usage:"
echo "    • Click the ${BOLD}ZeroTrace${NC} icon in your app menu"
echo "    • Or run ${BOLD}zerotrace${NC} in the terminal"
echo "    • Or run ${BOLD}zerotrace --dry-run${NC} to preview"
echo ""
echo "  The background listener starts automatically"
echo "  on your next login — it will show the cleanup"
echo "  dialog when you log out or switch users."
echo ""
echo "  To uninstall:"
echo "    ${BOLD}~/.local/share/zerotrace/uninstall.sh${NC}"
echo ""
