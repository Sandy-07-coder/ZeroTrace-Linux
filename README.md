# ZeroTrace OS — Session Sanitizer

**ZeroTrace** is a Bash-based CLI tool that sanitizes leftover session data on shared Ubuntu machines (college labs, cyber cafés). It targets specific known-leaky locations — temp directories and browser artefacts — and produces a clear report of exactly what was cleaned.

## Why ZeroTrace?

| Tool | Problem |
|---|---|
| CCleaner / BleachBit | Manual per-run config, no audit trail |
| Deep Freeze | Resets the *entire* disk, overkill |
| **ZeroTrace** | Targets only known-leaky paths, produces a detailed report, safe to run repeatedly |

---

## Project Structure

```
zerotrace/
├── zerotrace.sh              # Core backend / CLI script (Phase 1)
├── zerotrace-gui.py          # GTK3 interactive UI (Phase 2)
├── zerotrace-listener.py     # D-Bus background trigger daemon (Phase 3)
├── zerotrace.desktop         # App grid launcher for the GUI
├── lib/
│   ├── targets.sh            # Target path definitions + Firefox profile discovery
│   ├── clean.sh              # Deletion routines (rm / shred wrappers)
│   ├── lockcheck.sh          # lsof + signal escalation logic
│   └── report.sh             # Summary formatting and logging helpers
├── tests/
│   └── simulate_session.sh   # Helper to create realistic session clutter
└── README.md
```

---

## Usage

### GUI & Automatic Triggers
ZeroTrace is deeply integrated into the GNOME session (Phase 2 & 3):
- **Automatic Logout/Switch-User Prompt:** A background listener (`zerotrace-listener.py`) hooks into the GNOME session and systemd. When you log out or switch users, a GTK GUI will automatically prompt you to clean the session.
- **Manual App Launcher:** You can also manually launch the ZeroTrace GUI from your application grid (requires installing `zerotrace.desktop`).

### CLI Usage

```bash
# Full clean with summary
./zerotrace.sh

# Show what WOULD be cleaned without deleting anything
./zerotrace.sh --dry-run

# Per-file verbose output + summary
./zerotrace.sh --verbose

# Combine both flags
./zerotrace.sh --dry-run --verbose

# Help
./zerotrace.sh --help
```

---

## What It Cleans

| Category | Target | Method |
|---|---|---|
| **Temp dirs** | `/tmp`, `/var/tmp` | `rm -rf` (contents only) |
| **Chrome** | `~/.config/google-chrome/Default/{Cookies,Web Data,History,…}` + `-wal`/`-shm` | `shred -u` |
| **Chromium** | `~/.config/chromium/Default/` equivalents | `shred -u` |
| **Firefox** | `~/.mozilla/firefox/<profile>/{cookies,formhistory,places}.sqlite` + `-wal`/`-shm` | `shred -u` |

- Firefox profile directories are **discovered dynamically** via `profiles.ini` — no hardcoding.
- Missing paths are **silently skipped** (not every machine has both browsers).

---

## Process-Lock Handling

Before deleting any file, ZeroTrace checks `lsof` for holding processes:

1. **Protected denylist** — `systemd`, `Xorg`, `gnome-shell`, `plasmashell`, `NetworkManager`, `sshd`, `init` are **never signalled**. Files held by these are skipped and logged.
2. Other processes receive **SIGTERM** and get up to 5 seconds to exit gracefully.
3. If still alive after 5 s, **SIGKILL** is sent.
4. Every termination (PID, process name, target file, graceful/forced) is logged in the report.

---

## Safety Constraints

- ✅ Never deletes outside the explicitly listed target paths.
- ✅ Always checks that a path exists and is the expected type before acting.
- ✅ **Idempotent** — running twice with nothing to clean produces a clean "already clean" report.
- ✅ Protected system processes are never touched.

---

## Testing

### Simulate session clutter

```bash
# Create realistic clutter across all target locations
./tests/simulate_session.sh

# Also open a browser process (for process-lock testing) — use on a VM snapshot!
./tests/simulate_session.sh --open-browser
```

### Acceptance test

```bash
# 1. Simulate clutter
./tests/simulate_session.sh --open-browser

# 2. Run ZeroTrace while browser is open — should handle lock gracefully
./zerotrace.sh --verbose

# 3. Run again — should report "already clean"
./zerotrace.sh

# 4. Verify
du -sh ~/.mozilla/firefox /tmp /var/tmp
ls ~/.config/google-chrome/Default/Cookies 2>/dev/null || echo "✓ cleaned"
```

---

## Requirements

- Ubuntu / Debian-based Linux (GNOME desktop required for auto-triggers)
- `bash` ≥ 4.0
- `lsof` (for process-lock detection — gracefully skipped if missing)
- `shred` (from GNU coreutils — zero+delete fallback used if missing)
- `python3` & `python3-gi` (PyGObject for GTK3 GUI)
- D-Bus and `systemd-logind` (for session lifecycle integration)


---

## Phase Roadmap

| Phase | Status | Description |
|---|---|---|
| Phase 1 | ✅ Completed | CLI-Based Session Sanitizer (Backend logic) |
| Phase 2 | ✅ Completed | Interactive Cleanup GUI (GTK3 application) |
| Phase 3 | ✅ Completed | D-Bus Session Integration (Automatic trigger on logout/switch-user) |
