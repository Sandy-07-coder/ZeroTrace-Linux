# ZeroTrace OS — Build Prompt (Phase 1 & Phase 2, Ubuntu/Linux)

Use this as the brief for an AI coding assistant (e.g. Claude Code) or as a team task spec. It covers Phase 1 (a manually-triggered CLI sanitization script) and Phase 2 (a GUI that surfaces on logout/switch-user and calls into the Phase 1 script), both scoped to Ubuntu.

---

## Project context

Build **ZeroTrace**, a tool that sanitizes leftover session data on a shared Ubuntu machine (college lab / cyber café use case). Unlike existing tools (CCleaner/BleachBit require manual per-run config and give no audit trail; Deep Freeze resets the whole disk), ZeroTrace targets *specific* known-leaky locations — temp dirs, per-app caches, browser WAL files, DNS cache — and produces a report of exactly what it cleaned. Phase 2 makes this interactive: instead of requiring a manual CLI run, a background listener catches the moment the user clicks **Log Out** or **Switch User** and offers to clean before that happens.

Encryption / crypto-shredding (Phase 3) is explicitly **not** part of this build — see "out of scope" below.

## Phase 1 Requirements

### 1.1 Target directories to clean

- `/tmp`
- `/var/tmp`
- `~/.cache` (all subdirectories, including `~/.cache/thumbnails`)
- Chrome/Chromium: `~/.config/google-chrome/Default/{Cookies,Cookies-journal,Web Data,Web Data-journal,History}` and `~/.config/chromium/Default/` equivalents, plus any `-wal`/`-shm` siblings
- Firefox: `~/.mozilla/firefox/<profile>/{cookies.sqlite,formhistory.sqlite,places.sqlite}` and their `-wal`/`-shm` siblings (profile directory name varies — the script must discover it, not hardcode it)

### 1.2 DNS cache flush

Run `sudo resolvectl flush-caches`. If `resolvectl` isn't available, fall back to `sudo systemd-resolve --flush-caches`. Fail gracefully (log a warning, don't abort the whole run) if neither exists.

### 1.3 Deletion logic

- `/tmp` and `/var/tmp`: straightforward `rm -rf` of contents (not the directories themselves).
- `~/.cache` and the browser files listed above: use `shred -u` where the file exists and is a regular file; if `shred` isn't available, fall back to overwrite-with-zeros-then-delete.
- Skip silently (don't error) on paths that don't exist — not every machine will have Chrome and Firefox both installed.

### 1.4 Process-lock handling

Before deleting any target file, check `lsof <path>` for a holding process:

1. If a process holds the file, send it `SIGTERM`.
2. Wait up to 5 seconds, polling whether the process has exited.
3. If it hasn't exited, send `SIGKILL`.
4. **Hard denylist — never send a signal to these, under any circumstance:** `systemd`, `Xorg`, `gnome-shell`, `plasmashell`, `NetworkManager`, `sshd`, `init`. If the holding process matches this list, skip that file, log it as "skipped — protected process," and move on.
5. Log every termination action taken: PID, process name, target file, graceful or forced.

### 1.5 Reporting

Print a summary at the end of the run:
- Count and total size of files/dirs cleaned per target category.
- Any targets that didn't exist (skipped, not an error).
- Any files that couldn't be cleaned (permission denied, protected-process lock) with the reason.
- DNS flush result (success/failure).

Keep this human-readable on stdout for Phase 1 — structured logging (SQLite) is a later-phase concern, not required here.

### 1.6 CLI interface

A single entry point, e.g. `./zerotrace.sh`, with:
- `--dry-run` — show what would be cleaned without deleting anything.
- `--verbose` — print each individual file action, not just the summary.
- No arguments — run the full clean with the standard summary output.

### 1.7 Safety constraints

- Never delete anything outside the explicitly listed target paths.
- Never run destructive actions without first checking the path exists and is of the expected type (file vs directory) to avoid accidentally globbing something unintended.
- The script must be safe to run repeatedly (idempotent) — running it twice in a row with nothing new to clean should complete cleanly with an "already clean" style summary, not error.

## Phase 1 Acceptance Criteria

1. Run `./tests/simulate_session.sh` on a fresh Ubuntu VM snapshot to create realistic clutter (open a browser, browse a few sites, generate a thumbnail, leave the browser running).
2. Run `./zerotrace.sh` while the browser is still open — it should gracefully close the browser's hold on its cache files (or escalate to `SIGKILL` if needed), clean all target paths, flush DNS, and print an accurate summary.
3. Run `./zerotrace.sh` again immediately — it should report "already clean" with no errors.
4. Confirm via `ls`/`du` that all target directories are empty or reset, and that no protected system process was touched.

---

## Phase 2 Requirements

### 2.1 Background listener

Build a Python daemon that runs persistently in the user's GNOME session (e.g. as a `systemd --user` service or a desktop autostart entry) and:

- Registers a logout inhibitor via `org.gnome.SessionManager.Inhibit()` with the `INHIBIT_LOGOUT` flag.
- Listens for the `QueryEndSession` signal — this is the real, reliable **Log Out** trigger.
- Separately monitors `org.freedesktop.login1` for `SessionNew` events where the new session's user differs from the current session's user — this is the best-effort **Switch User** trigger. Document in code comments that this is an approximation, since fast user switching doesn't end the original session.

### 2.2 GUI dialog

Build using **Python + PyGObject (GTK3)**:

- A modal dialog with a short explanatory message, a **Clean now** button, a **Skip** button, and a visible countdown (default 10 seconds).
- On countdown expiry with no response, default to **Clean now** (privacy-safe default).
- On **Clean now**: invoke the Phase 1 `zerotrace.sh` script as a subprocess and wait for it to complete (show a simple "cleaning..." state in the dialog) before proceeding.
- On **Skip** or after the clean completes: call `EndSessionResponse()` to release the inhibitor and allow the logout/switch to proceed.

### 2.3 Wiring to Phase 1

The GUI must not duplicate cleaning logic — it only ever shells out to the existing `zerotrace.sh`. Capture its exit code and stdout summary so the dialog can show a one-line result (e.g. "Cleaned 340MB" or "Some files could not be cleaned") before closing.

### 2.4 Safety constraints

- The listener must never block a logout indefinitely — if `zerotrace.sh` hangs, enforce a hard timeout (e.g. 30 seconds) after which the inhibitor is released and logout proceeds anyway, so a bug in Phase 1 can never lock a user out of logging off their own machine.
- The switch-user detection must never attempt to inhibit or delay the switch itself (there's no clean mechanism for that) — it only shows the dialog as an informational/optional prompt.

## Suggested repo structure

```
zerotrace/
├── zerotrace.sh               # Phase 1 entry point / CLI
├── lib/
│   ├── targets.sh             # target path definitions + discovery (e.g. Firefox profile lookup)
│   ├── clean.sh                # deletion routines (rm / shred wrappers)
│   ├── lockcheck.sh           # lsof + signal escalation logic
│   └── report.sh               # summary formatting
├── gui/
│   ├── listener.py            # Phase 2 background daemon (D-Bus inhibitor + session monitoring)
│   ├── dialog.py               # GTK dialog (Clean now / Skip / countdown)
│   └── zerotrace-gui.service  # systemd --user unit to autostart the listener
├── tests/
│   └── simulate_session.sh    # helper to dirty up a test VM before running zerotrace.sh
└── README.md
```

## Phase 2 Acceptance Criteria

1. With the listener running, click **Log Out** from the GNOME top-right menu — the logout should visibly pause and the GTK dialog should appear.
2. Click **Clean now** — the dialog should show a cleaning state, then the logout should proceed once `zerotrace.sh` completes.
3. Repeat and click **Skip** — the logout should proceed immediately with no cleaning.
4. Repeat and let the countdown expire — cleaning should run automatically (default action), then logout proceeds.
5. Trigger **Switch User** — confirm the dialog appears for the outgoing session on a best-effort basis, and confirm skipping it does not block the switch.
6. Kill or hang the underlying `zerotrace.sh` process artificially and confirm the listener's timeout still releases the logout after the hard timeout, rather than hanging indefinitely.

## Explicitly out of scope for this build

- Encryption / tmpfs / crypto-shredding — that's Phase 3.
- Fair CPU/memory scheduling across sessions — later work, not part of the sanitization core.
- A full dashboard/reporting UI beyond the single Clean now/Skip dialog — Phase 2 is intentionally minimal.
