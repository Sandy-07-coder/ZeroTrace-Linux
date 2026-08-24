# ZeroTrace OS — Build Prompt (Phase 1, Ubuntu/Linux)
 
Use this as the brief for an AI coding assistant (e.g. Claude Code) or as a team task spec. It's scoped strictly to Phase 1 — a manually-triggered CLI sanitization script for Ubuntu.
 
---
 
## Project context
 
Build **ZeroTrace**, a Bash-based command-line tool that sanitizes leftover session data on a shared Ubuntu machine (college lab / cyber café use case). Unlike existing tools (CCleaner/BleachBit require manual per-run config and give no audit trail; Deep Freeze resets the whole disk), ZeroTrace targets *specific* known-leaky locations — temp dirs, per-app caches, browser WAL files, DNS cache — and produces a report of exactly what it cleaned.
 
This is Phase 1 only: **manual invocation, no automatic logout trigger, no encryption.** Those come later.
 
## Requirements
 
### 1. Target directories to clean
 
- `/tmp`
- `/var/tmp`
- `~/.cache` (all subdirectories, including `~/.cache/thumbnails`)
- Chrome/Chromium: `~/.config/google-chrome/Default/{Cookies,Cookies-journal,Web Data,Web Data-journal,History}` and `~/.config/chromium/Default/` equivalents, plus any `-wal`/`-shm` siblings
- Firefox: `~/.mozilla/firefox/<profile>/{cookies.sqlite,formhistory.sqlite,places.sqlite}` and their `-wal`/`-shm` siblings (profile directory name varies — the script must discover it, not hardcode it)
### 2. DNS cache flush
 
Run `sudo resolvectl flush-caches`. If `resolvectl` isn't available, fall back to `sudo systemd-resolve --flush-caches`. Fail gracefully (log a warning, don't abort the whole run) if neither exists.
 
### 3. Deletion logic
 
- `/tmp` and `/var/tmp`: straightforward `rm -rf` of contents (not the directories themselves).
- `~/.cache` and the browser files listed above: use `shred -u` where the file exists and is a regular file; if `shred` isn't available, fall back to overwrite-with-zeros-then-delete.
- Skip silently (don't error) on paths that don't exist — not every machine will have Chrome and Firefox both installed.
### 4. Process-lock handling
 
Before deleting any target file, check `lsof <path>` for a holding process:
 
1. If a process holds the file, send it `SIGTERM`.
2. Wait up to 5 seconds, polling whether the process has exited.
3. If it hasn't exited, send `SIGKILL`.
4. **Hard denylist — never send a signal to these, under any circumstance:** `systemd`, `Xorg`, `gnome-shell`, `plasmashell`, `NetworkManager`, `sshd`, `init`. If the holding process matches this list, skip that file, log it as "skipped — protected process," and move on.
5. Log every termination action taken: PID, process name, target file, graceful or forced.
### 5. Reporting
 
Print a summary at the end of the run:
- Count and total size of files/dirs cleaned per target category.
- Any targets that didn't exist (skipped, not an error).
- Any files that couldn't be cleaned (permission denied, protected-process lock) with the reason.
- DNS flush result (success/failure).
Keep this human-readable on stdout for Phase 1 — structured logging (SQLite) is a later-phase concern, not required here.
 
### 6. CLI interface
 
A single entry point, e.g. `./zerotrace.sh`, with:
- `--dry-run` — show what would be cleaned without deleting anything.
- `--verbose` — print each individual file action, not just the summary.
- No arguments — run the full clean with the standard summary output.
### 7. Safety constraints
 
- Never delete anything outside the explicitly listed target paths.
- Never run destructive actions without first checking the path exists and is of the expected type (file vs directory) to avoid accidentally globbing something unintended.
- The script must be safe to run repeatedly (idempotent) — running it twice in a row with nothing new to clean should complete cleanly with an "already clean" style summary, not error.
## Suggested repo structure
 
```
zerotrace/
├── zerotrace.sh              # main entry point / CLI
├── lib/
│   ├── targets.sh            # target path definitions + discovery (e.g. Firefox profile lookup)
│   ├── clean.sh               # deletion routines (rm / shred wrappers)
│   ├── lockcheck.sh          # lsof + signal escalation logic
│   └── report.sh              # summary formatting
├── tests/
│   └── simulate_session.sh   # helper to dirty up a test VM before running zerotrace.sh
└── README.md
```
 
## Acceptance criteria (how to know Phase 1 is done)
 
1. Run `./tests/simulate_session.sh` on a fresh Ubuntu VM snapshot to create realistic clutter (open a browser, browse a few sites, generate a thumbnail, leave the browser running).
2. Run `./zerotrace.sh` while the browser is still open — it should gracefully close the browser's hold on its cache files (or escalate to `SIGKILL` if needed), clean all target paths, flush DNS, and print an accurate summary.
3. Run `./zerotrace.sh` again immediately — it should report "already clean" with no errors.
4. Confirm via `ls`/`du` that all target directories are empty or reset, and that no protected system process was touched.
## Explicitly out of scope for this build
 
- The Phase 2 GUI (logout/switch-user trigger, dialog, background listener) — separate build.
- Encryption / tmpfs / crypto-shredding — that's Phase 3.
- Fair CPU/memory scheduling across sessions — later work, not part of the sanitization core.
- A GUI dashboard — Phase 1 is CLI-only.
 
