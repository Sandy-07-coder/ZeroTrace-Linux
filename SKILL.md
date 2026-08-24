# ZeroTrace OS — Skills & Prerequisites

*Scope: Linux (Ubuntu) only.* A reference for what the team needs to know to build Phase 1, Phase 2, and Phase 3. Organized so each contributor can check the sections relevant to their module.

## Ubuntu file locations

- `/tmp`, `/var/tmp` — system-wide temp workspaces.
- XDG Base Directory spec — `~/.cache` (per-app caches), `~/.config` (app configs, where browser profiles live).
- How `systemd-resolved` caches DNS, and how to flush it (`resolvectl flush-caches`).

## Scripting

- **Bash** — safe scripting practices (`set -euo pipefail`), `find`/`xargs` for bulk operations, `trap` for cleanup on script interruption.
- **Python** (for the daemon/CLI layer in later work) — `subprocess` for shelling out to system tools, `argparse`/`click` for CLI structure, `sqlite3` for logging.
- **Python + PyGObject (GTK3)** (for the Phase 2 GUI) — building a simple dialog window, timers/countdowns in the GTK main loop, and running GTK code inside a background daemon process.

## Process & file-lock management

- `lsof` to find which process holds a file open.
- Signals — the difference between `SIGTERM` (ask nicely, process can clean up) and `SIGKILL` (immediate, no cleanup), and why you always try the former first with a grace period.
- Why force-killing the wrong process (a compositor, a system service) can crash or destabilize the desktop session, and how to build a denylist to prevent it.

## Application internals

- SQLite storage format basics — enough to know a `-wal` (write-ahead log) file can hold data not yet in the main `.sqlite`/`Cookies`/`Web Data` file, and that both must be cleared together.
- Chrome/Chromium and Firefox profile layout on Linux — where cookies, autofill, and cache live within `~/.config/google-chrome/` and `~/.mozilla/firefox/`.
- Thumbnail cache format (`~/.cache/thumbnails/`) — that thumbnails can leak file existence even after the source file and its cache entry are otherwise gone.

## Session & desktop events (Phase 2 — GUI trigger)

- `systemd-logind` D-Bus signals (`SessionNew`, `SessionRemoved` on `org.freedesktop.login1`) — how to listen for them via `python-dbus` or `pystemd`, and how to tell which user a session belongs to (for switch-user detection).
- `org.gnome.SessionManager` D-Bus interface — registering an **inhibitor** (`Inhibit()` with `INHIBIT_LOGOUT`), listening for `QueryEndSession`, and calling `EndSessionResponse()` to release it. This is the mechanism that lets an app pause a real logout click and show a dialog first.
- PAM session hooks (`pam_exec.so`) as a simpler, more fragile alternative for basic triggers.
- The distinction between **logout** (session actually ends — a hard, reliable trigger) and **switch user** (session is only backgrounded/locked — a soft, best-effort trigger with no dedicated D-Bus signal). Understand why this asymmetry exists before designing the GUI's behavior around it.
- GTK dialog basics: modal windows, a countdown timer using `GLib.timeout_add()`, and running a small always-on background daemon under the user's session (e.g. as a systemd user service or autostart entry) so the listener is alive to catch the trigger.

## Phase 3 — cryptographic erasure concepts

- **tmpfs** — a RAM-backed filesystem; understand mount options (`mount -t tmpfs`), size limits, and that its contents never touch the physical disk and vanish on unmount/reboot.
- **Ephemeral key management** — generating a cryptographically secure random key (`os.urandom`), keeping it exclusively in process memory (never written to disk), and the security argument for why this matters.
- **Crypto-shredding** — the concept that destroying the encryption key makes ciphertext permanently unrecoverable, without needing to overwrite the underlying storage. Understand *why* this is faster and equally secure compared to multi-pass disk wiping.
- **Memory protection basics** — why an in-memory key could still leak via swap if the process's memory isn't protected (`mlock()` on Linux), and why that matters once Phase 3 depends on the key never touching disk.
- **dm-crypt / LUKS on a loop device** as an alternative to plain tmpfs if you want on-disk-but-encrypted storage instead of pure-RAM storage — useful to know as a fallback if tmpfs size limits become a problem for large caches.

## Testing & validation

- Building and using VM snapshots (VirtualBox) so destructive tests (killing processes, mounting/unmounting encrypted volumes) are always reversible.
- Basic forensic verification techniques: `strings`/`grep` against a raw device or file to confirm target data is actually gone, not just deleted from a directory listing.

## Collaboration & tooling

- Git branching by module, PR review before merging to `main`.
- Writing a shared "interface contract" (function signatures, data shapes) before parallel work starts, so modules integrate without conflict.
