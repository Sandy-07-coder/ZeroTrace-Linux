# ZeroTrace OS — Phase 1: Baseline Architecture & Targeted Sanitization (Proof of Concept)

*Scope: Linux (Ubuntu) only.*

## Focus

Mapping attack surfaces, targeting application-specific transient directories, and establishing reliable teardown scripts. This phase proves the core sanitization concept as a manually-triggered script before any automation, encryption, or scheduling work is added.

## Objectives

- Identify every location on an Ubuntu system where a session can leave recoverable, sensitive data behind.
- Build a script that reliably deletes that data on demand.
- Handle the hard part cleanly: files and caches locked by still-running processes, without crashing the OS or losing unrelated user data.
- Ship something demoable: run the script, show the target directories were dirty, run it, show they're clean.

## Directory Mapping & Target Identification

### System & user temp workspaces

| Path | Notes |
|---|---|
| `/tmp` | Cleared on reboot by most distros, not on logout — anything written mid-session persists until reboot |
| `/var/tmp` | Persists across reboots too — higher leak risk |
| `~/.cache` | XDG-standard per-app cache directory (thumbnails, app scratch data, browser cache) |

### Application-specific databases & caches

- **Chrome/Chromium SQLite WAL caches** — `Cookies`, `Web Data` (autofill), `History` under `~/.config/google-chrome/Default/` (or `~/.config/chromium/Default/`), plus their `-wal`/`-shm` write-ahead-log siblings. The WAL is the trap: data can sit in the WAL and not yet be checkpointed into the main DB, so deleting only the main file leaves recoverable data behind — both must be cleared together.
- **Firefox equivalent** — `~/.mozilla/firefox/<profile>/cookies.sqlite`, `formhistory.sqlite`, `places.sqlite` (history), same WAL caveat applies (`*-wal`, `*-shm`).
- **Thumbnail cache** — `~/.cache/thumbnails/`. Thumbnails can leak that a specific image/document existed even after the original file is gone.
- **DNS cache** — an in-memory OS-level cache of resolved hostnames, revealing which sites/services a session visited. Not a file to delete — needs an explicit flush command (`resolvectl flush-caches` on systemd-resolved systems, the default on modern Ubuntu).

## Scripted Cleaning Logic

### Language choice

**Bash**, with a Python wrapper if you want structured logging/CLI flags layered on top later (see `build_prompt.md` for the fuller architecture). For the Phase 1 milestone, a self-contained Bash script is sufficient and matches the "standalone script" deliverable.

### Deletion routines

- Plain `rm -rf` is fine for low-sensitivity scratch files (`/tmp`, `/var/tmp`) where speed matters more than forensic certainty.
- Use `shred -u` (or an overwrite-then-`rm`) for the higher-value targets: browser cookie/autofill/WAL files and thumbnail cache — this is the differentiator called out in your innovation slide (targets the layer other tools ignore).
- DNS cache flush: `sudo resolvectl flush-caches` (systemd-resolved, default on Ubuntu 18.04+). Fall back to `sudo systemd-resolve --flush-caches` on older systems if `resolvectl` isn't present.

### Process-termination handling (the hard requirement)

Files under active use (an open browser, an IDE holding a lock on its cache) will refuse to delete or will corrupt if force-deleted carelessly. The script must:

1. **Detect locks before acting** — `lsof <path>` to list processes holding a file open.
2. **Prefer graceful closure** — send the owning process `SIGTERM` and give it a short grace period (a few seconds) to release the file and exit cleanly.
3. **Escalate only if needed** — send `SIGKILL` only after the grace period expires, and only to the specific process holding the specific target file — never a blanket kill pass.
4. **Never touch protected system processes** — maintain an explicit denylist (`systemd`, `Xorg`, `gnome-shell`/`plasmashell`, `NetworkManager`, etc.) that the script will not attempt to terminate under any circumstance, to avoid crashing the desktop session or the OS.
5. **Log every termination action** — which process (PID + name), which file, graceful or forced — so there's an audit trail of what the script did.

## Milestone Deliverable

A standalone, functional Bash script, executable via CLI, that on manual invocation:

- Cleans `/tmp`, `/var/tmp`, `~/.cache` (including thumbnails), and browser cookie/autofill/history/WAL files.
- Flushes the DNS cache.
- Handles locked files via the graceful-then-forced termination sequence above, without crashing the OS.
- Prints (or logs) a summary of what was cleaned and what, if anything, could not be cleaned.

## Testing Approach

- Run inside a VirtualBox Ubuntu VM snapshot so process-termination edge cases are safe to test.
- Simulate a "dirty" session: open a browser, visit a few sites, open/close a document, let thumbnails generate — then run the script and verify each target directory is empty/reset and DNS cache is flushed.
- Deliberately leave a file locked (keep the browser open) and confirm the script's grace-period-then-escalate logic behaves as designed instead of hanging or crashing the session.

## Relationship to Later Work

Phase 1 is intentionally manual and single-shot — no automatic logout trigger, no encryption, no fair scheduling. Those belong to later work: automatic invocation via `systemd-logind` hooks, and the ephemeral encrypted storage work in Phase 2 (`tmpfs`-backed `~/.cache` and temp with an in-memory-only session key and crypto-shredding on logout). Keeping Phase 1 narrow is what makes it achievable as a proof-of-concept within a short timeline.
