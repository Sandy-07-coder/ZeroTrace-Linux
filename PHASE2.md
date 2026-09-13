# ZeroTrace OS — Phase 2: Interactive Cleanup GUI

*Scope: Linux (Ubuntu, GNOME desktop) only.*

## Focus

Wrap the Phase 1 CLI script in a graphical interface so that users who aren't comfortable with the terminal can trigger session cleanup with a button click. This phase is purely a UI layer on top of Phase 1 — no new cleaning logic, no session lifecycle integration (that's Phase 3).

## Objectives

- Build a GTK3 desktop application that lets the user trigger the Phase 1 cleanup visually.
- Show real-time progress and output from the cleaning script.
- Provide a cleanup history log so users can verify past runs.
- Include a countdown timer with a sensible default action (auto-clean) for unattended use.

## GUI Design

- **Toolkit: Python + PyGObject (GTK3)** — native GNOME look and feel, lightweight, no Electron overhead.
- **Main window contents:**
  - A short message explaining what will be cleaned (temp files, browser cache, cookies/autofill) and why (privacy on a shared machine).
  - Two buttons: **Clean Now** and **Skip**.
  - A 10-second countdown — if the user doesn't respond, defaults to **Clean Now** (privacy-safe default: leaving stale data behind is the worse outcome).
  - An expandable "Show Details" panel with real-time monospace output from the Phase 1 script.
- **On "Clean Now":** invoke `zerotrace.sh` as a subprocess, stream output to the details panel, log the result.
- **On "Skip":** close the window with no action.

## Additional Features

### Cleanup History

- SQLite database at `~/.local/share/zerotrace/logs.db` storing timestamp, status (Success/Failed), and full output of each cleanup run.
- A "Logs" dialog accessible from the header bar showing past runs in a table view.

### Settings

- A "Settings" dialog with a toggle for **Dry Run Mode** — lets the user preview what would be cleaned without actually deleting anything (passes `--dry-run` to the Phase 1 script).

## Architecture

```
zerotrace-gui.py (GTK3 application)
        │
        ├─ Main window with Clean Now / Skip / countdown
        ├─ Calls zerotrace.sh [--dry-run] as subprocess
        ├─ Streams stdout to real-time output panel
        ├─ Logs result to SQLite database
        │
        ├─ Settings dialog (dry-run toggle)
        └─ Logs dialog (cleanup history viewer)
```

## Desktop Launcher

A `.desktop` file is provided so users can launch ZeroTrace from the GNOME Activities menu / app grid without opening a terminal.

### File: `zerotrace.desktop`

```ini
[Desktop Entry]
Type=Application
Name=ZeroTrace
Comment=Clean session traces on shared machines
Exec=python3 /path/to/zerotrace-gui.py
Icon=security-high
Terminal=false
Categories=Utility;System;
```

### Installation

Copy the file to the user's local applications directory:

```bash
cp zerotrace.desktop ~/.local/share/applications/
```

After copying, ZeroTrace appears in the GNOME app grid. The user clicks the icon, the Phase 2 GUI opens, and they can clean or skip as usual.

> **Note:** Update the `Exec=` path to the actual install location of `zerotrace-gui.py`. To use a custom icon instead of the system `security-high` icon, set `Icon=` to an absolute path (e.g., `Icon=/path/to/zerotrace-icon.png`).

## No Root Privileges Required

The Phase 1 backend script checks ownership and only targets user-owned files. The GUI and script run entirely in user-space without requiring `sudo` or `polkit`.

## Milestone Deliverable

A standalone GTK3 application (`zerotrace-gui.py`) that:

- Launches as a desktop window with a clean, GNOME-native look.
- Shows the countdown and auto-triggers cleanup if the user doesn't interact.
- Invokes the Phase 1 script and displays real-time output.
- Persists cleanup history in a local SQLite database.
- Provides settings (dry-run toggle) and a log viewer.

## Testing Approach

- Launch the GUI manually and confirm it invokes the Phase 1 script correctly.
- Test the countdown — let it expire without clicking and confirm auto-clean fires.
- Click "Skip" and confirm no cleanup runs.
- Click "Clean Now" and confirm the details panel streams output in real time.
- Check the Logs dialog shows the correct history after multiple runs.
- Toggle dry-run mode in Settings and confirm the script receives the `--dry-run` flag.

## Relationship to Phase 1 and Phase 3

Phase 2 is a UI wrapper — it calls the Phase 1 script, it doesn't reimplement cleaning logic. Phase 3 will add D-Bus session integration so this GUI is automatically shown when the user clicks Log Out or Switch User, instead of requiring a manual launch. The GUI itself won't need to change — Phase 3 adds the trigger that opens it at the right moment.
