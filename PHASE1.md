# ZeroTrace OS — Phase 1: CLI-Based Session Sanitizer (Proof of Concept)

*Scope: Linux (Ubuntu) only.*

## Focus

A standalone, manually-triggered Bash script that maps attack surfaces, targets application-specific transient directories, and reliably sanitizes session data on demand. This phase proves the core cleaning concept before any GUI or automation work is added.

## Objectives

- Identify every location on an Ubuntu system where a session can leave recoverable, sensitive data behind.
- Build a script that reliably deletes that data on demand via the command line.
- Handle files and caches locked by still-running processes, without crashing the OS or losing unrelated user data.
- Ship something demoable: run the script, show the target directories were dirty, run it again, show they're clean.

## Directory Mapping & Target Identification

### System & user temp workspaces

| Path | Notes |
|---|---|
| `/tmp` | Cleared on reboot by most distros, not on logout — anything written mid-session persists until reboot |
| `/var/tmp` | Persists across reboots too — higher leak risk |

### Application-specific databases & caches

- **Chrome/Chromium SQLite WAL caches** — `Cookies`, `Web Data` (autofill), `History` under `~/.config/google-chrome/Default/` (or `~/.config/chromium/Default/`), plus their `-wal`/`-shm` write-ahead-log siblings. The WAL is the trap: data can sit in the WAL and not yet be checkpointed into the main DB, so deleting only the main file leaves recoverable data behind — both must be cleared together.
- **Firefox equivalent** — `~/.mozilla/firefox/<profile>/cookies.sqlite`, `formhistory.sqlite`, `places.sqlite` (history), same WAL caveat applies (`*-wal`, `*-shm`).

## Scripted Cleaning Logic

### Language choice

**Bash**, with a modular library structure (`lib/` directory for targets, cleaning, lock handling, and reporting). For Phase 1, a self-contained Bash script is sufficient and matches the "standalone CLI script" deliverable.

### Deletion routines

- Plain `rm -rf` for low-sensitivity scratch files (`/tmp`, `/var/tmp`) where speed matters more than forensic certainty.
- `shred -u` (with an overwrite-then-`rm` fallback) for higher-value targets: browser cookie/autofill/WAL files.

### Process-termination handling

Files under active use (an open browser, an IDE holding a lock on its cache) will refuse to delete or will corrupt if force-deleted carelessly. The script must:

1. **Detect locks before acting** — `lsof <path>` to list processes holding a file open.
2. **Prefer graceful closure** — send the owning process `SIGTERM` and give it a short grace period (a few seconds) to release the file and exit cleanly.
3. **Escalate only if needed** — send `SIGKILL` only after the grace period expires, and only to the specific process holding the specific target file — never a blanket kill pass.
4. **Never touch protected system processes** — maintain an explicit denylist (`systemd`, `Xorg`, `gnome-shell`/`plasmashell`, `NetworkManager`, etc.) that the script will not attempt to terminate under any circumstance.
5. **Log every termination action** — which process (PID + name), which file, graceful or forced — so there's an audit trail of what the script did.

## Milestone Deliverable

A standalone, functional Bash script, executable via CLI, that on manual invocation:

- Cleans `/tmp`, `/var/tmp`, and browser cookie/autofill/history/WAL files.
- Handles locked files via the graceful-then-forced termination sequence above, without crashing the OS.
- Supports `--dry-run` and `--verbose` flags.
- Prints a summary report of what was cleaned, what was skipped, and what failed.

## Testing Approach

- Run inside a VirtualBox Ubuntu VM snapshot so process-termination edge cases are safe to test.
- Use the simulation script (`tests/simulate_session.sh`) to create realistic session clutter, then run the cleaner and verify each target is sanitized.
- Deliberately leave a file locked (keep a browser open) and confirm the grace-period-then-escalate logic works correctly.

## Relationship to Later Work

Phase 1 is the backend engine. Phase 2 wraps it in a GUI. Phase 3 hooks the GUI into real session lifecycle events (logout/switch-user) via D-Bus so it triggers automatically. The CLI script remains the single source of cleaning logic throughout — later phases call into it, they don't rewrite it.
