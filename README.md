# ZeroTrace — Session Sanitizer (Phase 1)

**ZeroTrace** is a Bash-based CLI tool that sanitizes leftover session data on shared Ubuntu machines (college labs, cyber cafés). It targets specific known-leaky locations — temp directories, user cache, browser artefacts, and DNS cache — and produces a clear report of exactly what was cleaned.

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
├── zerotrace.sh              # Main entry point / CLI
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
| **User cache** | `~/.cache` (all subdirs incl. thumbnails) | `shred -u` (or zero+delete fallback) |
| **Chrome** | `~/.config/google-chrome/Default/{Cookies,Web Data,History,…}` + `-wal`/`-shm` | `shred -u` |
| **Chromium** | `~/.config/chromium/Default/` equivalents | `shred -u` |
| **Firefox** | `~/.mozilla/firefox/<profile>/{cookies,formhistory,places}.sqlite` + `-wal`/`-shm` | `shred -u` |
| **DNS cache** | `resolvectl flush-caches` (systemd-resolve fallback) | system call |

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
du -sh ~/.cache ~/.mozilla/firefox /tmp /var/tmp
ls ~/.config/google-chrome/Default/Cookies 2>/dev/null || echo "✓ cleaned"
```

---

## Requirements

- Ubuntu / Debian-based Linux
- `bash` ≥ 4.0
- `lsof` (for process-lock detection — gracefully skipped if missing)
- `shred` (from GNU coreutils — zero+delete fallback used if missing)
- `sudo` privileges (for DNS cache flush)

---

## Phase Roadmap

| Phase | Status | Description |
|---|---|---|
| **Phase 1** | ✅ **This release** | Manual CLI sanitizer |
| Phase 2 | 🔜 Planned | GUI logout/switch-user trigger (GTK3 dialog + systemd-logind) |
| Phase 3 | 🔜 Planned | Cryptographic erasure via ephemeral keys + tmpfs |
