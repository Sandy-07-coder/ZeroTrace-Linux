#!/usr/bin/env bash
# uninstall.sh — Remove ZeroTrace from the system

set -euo pipefail

INSTALL_DIR="$HOME/.local/share/zerotrace"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
AUTOSTART_DIR="$HOME/.config/autostart"

GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

ok() { echo -e "  ${GREEN}✓${NC} $1"; }

echo ""
echo -e "${BOLD}Uninstalling ZeroTrace...${NC}"
echo ""

# Kill listener if running
pkill -f "zerotrace-listener.py" 2>/dev/null && ok "Stopped running listener" || true

# Remove autostart
rm -f "$AUTOSTART_DIR/zerotrace-listener.desktop"
ok "Removed autostart entry"

# Remove desktop launcher
rm -f "$DESKTOP_DIR/zerotrace.desktop"
ok "Removed desktop launcher"

# Remove CLI wrapper
rm -f "$BIN_DIR/zerotrace"
ok "Removed CLI command"

# Remove installed files
rm -rf "$INSTALL_DIR"
ok "Removed installed files"

echo ""
echo -e "${GREEN}${BOLD}  ZeroTrace uninstalled.${NC}"
echo ""
