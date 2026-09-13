# ZeroTrace OS — Phase 3: D-Bus Session Integration (Automatic Trigger)

*Scope: Linux (Ubuntu, GNOME desktop) only.*

## Focus

Make the Phase 2 GUI appear automatically at the moment it matters — when the user clicks **Log Out** or **Switch User** from Ubuntu's GNOME session menu. Instead of requiring a manual launch, ZeroTrace becomes a seamless part of the session lifecycle.

## Objectives

- Detect the two trigger moments: logout and switch-user.
- Automatically launch the Phase 2 GUI dialog when either event is detected.
- Pause the logout sequence until the user responds (or the countdown expires), then let it proceed.
- Run as a lightweight background listener that starts with the user session.

## Trigger Mechanisms

### Logout trigger (reliable)

GNOME's session manager (`org.gnome.SessionManager` over D-Bus) supports registering an **inhibitor** that pauses the logout sequence:

1. Call `Inhibit()` with the `INHIBIT_LOGOUT` flag when ZeroTrace's background listener starts, registering it as a participant in the end-session negotiation.
2. Listen for the `QueryEndSession` signal — this fires when the user clicks **Log Out**, before the session actually ends.
3. On receiving it, launch the Phase 2 GUI dialog.
4. Once the user responds (clean now / skip) or the countdown expires, call `EndSessionResponse()` to release the inhibitor and let the logout proceed.

This is the same mechanism apps use to show "you have unsaved changes" dialogs on logout — ZeroTrace uses it for cleanup instead.

### Switch-user trigger (best-effort)

Ubuntu's fast user switching does **not** end the current session — it locks it in the background and starts a new login screen. There's no direct "switch user was clicked" signal. The practical approach:

- Monitor `systemd-logind` for a `SessionNew` signal where the new session belongs to a **different user** than the currently active one (via `loginctl` / the `org.freedesktop.login1` D-Bus interface).
- When detected, launch the Phase 2 GUI for the outgoing user's session, since their session is about to sit idle while someone else uses the machine.
- **Caveat:** because the original session isn't actually ending, the display may switch to the login screen before the user can see the dialog. The 10-second countdown will auto-trigger "Clean Now" as the default, ensuring cleanup happens even if the dialog goes unseen.

## Architecture

```
zerotrace-listener.py (background daemon, runs in user session)
        │
        ├─ Registers logout inhibitor via org.gnome.SessionManager (D-Bus)
        ├─ Listens for QueryEndSession signal (logout)
        ├─ Listens for SessionNew signal on org.freedesktop.login1 (switch-user)
        │
        ▼
   Trigger detected
        │
        ▼
Launches zerotrace-gui.py (Phase 2 GUI)
        │
        ├─ Clean Now → Phase 1 zerotrace.sh runs → cleanup completes
        └─ Skip / Close → no action
        │
        ▼
EndSessionResponse() called → logout/switch proceeds normally
```

## Autostart

The background listener should start automatically with the GNOME session. This can be done via:

- A `.desktop` file in `~/.config/autostart/` pointing to `zerotrace-listener.py`.
- The `X-GNOME-Autostart-enabled=true` key ensures it launches on login.

## Design Constraints

1. **GNOME Logout Timeout:** GNOME's session manager enforces a hard timeout (~60 seconds) for logout inhibitors. The Phase 1 script must finish within this limit, otherwise GNOME will forcefully kill the process mid-cleanup.
2. **Switch-User Blind Spot:** The display may switch away before the user sees the dialog. The countdown auto-clean default handles this — cleanup fires automatically after 10 seconds if no interaction occurs.
3. **No Root Privileges:** The listener, GUI, and cleaning script all run in user-space. No `sudo` or `polkit` needed.

## Milestone Deliverable

A background listener process (`zerotrace-listener.py`) that:

- Registers itself with GNOME's session manager and correctly intercepts a real logout click, pausing it until the user responds.
- Detects switch-user events on a best-effort basis via `systemd-logind`.
- Launches the Phase 2 GUI when a trigger fires.
- Correctly releases the logout inhibitor in all cases (clean, skip, timeout, window closed).
- Includes an autostart `.desktop` file for seamless session integration.

## Testing Approach

- Test in a VM with a GNOME desktop session (not headless — needs a real display).
- Trigger a real logout from the top-right menu and confirm the GUI appears and logout pauses until the user responds.
- Trigger a switch-user and confirm the GUI appears (or auto-cleans after countdown).
- Let the countdown expire without clicking and confirm the default "Clean Now" action fires.
- Close the dialog window (X button) and confirm the inhibitor is released and logout proceeds.
- Confirm the autostart `.desktop` file works — log out and back in, and verify the listener is running.

## Relationship to Phase 1 and Phase 2

Phase 1 is the cleaning engine (CLI). Phase 2 is the visual interface (GUI). Phase 3 is the glue that connects the GUI to real session events — it doesn't change what gets cleaned or how the GUI looks, it just makes the GUI appear at the right moment automatically. The three phases stack: Phase 3 triggers Phase 2, which calls Phase 1.
