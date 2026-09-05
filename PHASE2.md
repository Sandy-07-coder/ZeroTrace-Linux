# ZeroTrace OS — Phase 2: Interactive Cleanup GUI (Logout / Switch-User Trigger)

*Scope: Linux (Ubuntu, GNOME desktop) only.*

## Focus

Turn the Phase 1 manual script into something that surfaces itself at the moment it matters: when the user is about to log out or switch to another user. Instead of running silently or requiring the user to remember to run a CLI command, ZeroTrace pops a GUI dialog at that moment asking whether to clean up now.

## Objectives

- Detect the two trigger moments: the user clicking **Log Out** and the user clicking **Switch User**, from Ubuntu's top-right GNOME session menu.
- Show a lightweight GUI dialog offering the choice to delete temp/cache files before the session actually ends or switches.
- On confirmation, call into the Phase 1 cleaning script as the backend — Phase 2 is a UI/trigger layer on top of Phase 1, not a rewrite of the cleaning logic.

## Trigger Mechanisms

### Logout trigger (reliable)

GNOME's session manager (`org.gnome.SessionManager` over D-Bus) supports registering an **inhibitor** that pauses the logout sequence so an app can intervene:

1. Call `Inhibit()` with the `INHIBIT_LOGOUT` flag when ZeroTrace's background listener starts, registering it as a participant in the end-session negotiation.
2. Listen for the `QueryEndSession` signal — this fires when the user clicks **Log Out**, before the session actually ends.
3. On receiving it, show the GUI dialog (see below).
4. Once the user responds (clean now / skip), call `EndSessionResponse()` to release the inhibitor and let the logout proceed.

This is the same mechanism apps use to show "you have unsaved changes" dialogs on logout — ZeroTrace is doing the same thing for a different purpose.

### Switch-user trigger (approximate)

Ubuntu's fast user switching does **not** end the current session — it locks it in the background and starts a new login screen for the other user. There's no direct "switch user was clicked" signal exposed the way logout has one. The practical approach:

- Monitor `systemd-logind` for a `SessionNew` signal where the new session belongs to a **different user** than the currently active one (via `loginctl` / the `org.freedesktop.login1` D-Bus interface).
- When detected, show the same GUI dialog to the outgoing user's session, since their session is about to sit idle/locked while someone else uses the machine.
- **Caveat to document clearly in your report:** because the original session isn't actually ending, "declining" cleanup here just means the old session's temp/cache stays as-is in the background — this is a softer, best-effort trigger compared to the logout case, not a hard guarantee.

## GUI Design

- **Toolkit: Python + PyGObject (GTK3)** — native GNOME look and feel, lighter weight than Electron, and consistent with the "lightweight" positioning from your innovation slide.
- **Dialog contents:**
  - A short message: what will be cleaned (temp files, browser cache, cookies/autofill) and why (privacy on a shared machine).
  - Two buttons: **Clean now** and **Skip**.
  - A short countdown (e.g. 10 seconds) with a sensible default action if the user doesn't respond — recommend defaulting to **Clean now** for the logout case (privacy-safe default), since if no one is watching, leaving stale session data behind is the worse outcome.
- **On "Clean now":** invoke the Phase 1 script (e.g. `zerotrace.sh`) as a subprocess, optionally showing a brief progress indicator, then let the logout/switch proceed.
- **On "Skip":** release the inhibitor / take no action and let the logout/switch proceed immediately.

## Architecture

```
Background listener (Python, runs in user session)
        │
        ├─ Registers logout inhibitor via org.gnome.SessionManager
        ├─ Listens for QueryEndSession (logout) and SessionNew-for-other-user (switch)
        │
        ▼
   Trigger detected
        │
        ▼
GTK dialog shown (Clean now / Skip, with countdown default)
        │
        ├─ Clean now → calls Phase 1 zerotrace.sh → waits for completion
        └─ Skip      → no action
        │
        ▼
Inhibitor released → logout/switch proceeds normally
```

## Milestone Deliverable

A background listener process that:
- Registers itself with GNOME's session manager and correctly intercepts a real logout click, pausing it until the user responds.
- Detects a switch-user event on a best-effort basis.
- Shows a GTK dialog with a working countdown and default action.
- Successfully invokes the Phase 1 script on confirmation and correctly allows the logout/switch to proceed afterward in all cases (clean, skip, and timeout).

## Testing Approach

- Test in a VM with a GNOME desktop session (not headless — this phase needs a real display).
- Trigger a real logout click from the top-right menu and confirm the dialog appears and the logout actually pauses until you respond.
- Trigger a switch-user click and confirm the dialog appears for the outgoing session.
- Let the countdown expire without clicking anything and confirm the default action fires correctly.
- Confirm the underlying Phase 1 script runs correctly when triggered this way (not just when run manually from a terminal).

## Relationship to Phase 1 and Phase 3

Phase 2 is a trigger + UI layer — it does not reimplement cleaning logic, it calls the Phase 1 script. Phase 3 (ephemeral encrypted storage via `tmpfs` and crypto-shredding) will eventually let the "Clean now" action become closer to instantaneous, since crypto-shredding a key is far faster than shredding files — at that point this GUI's backend call swaps from "run the Phase 1 delete script" to "destroy the Phase 3 session key," without needing to change the trigger or dialog logic.

## Design Decisions & Constraints (Q&A Updates)

Based on review, three critical design constraints have been explicitly agreed upon for Phase 2:

1. **Switch User Behavior (The "Blind Spot"):** When a user switches sessions, the display may switch to the login screen before the user can see the GTK dialog. We will proceed anyway and rely on the 10-second countdown to automatically trigger the default "Clean Now" action if the user doesn't see or interact with the dialog.
2. **GNOME Logout Timeout:** GNOME's session manager enforces a hard timeout (~60 seconds) for logout inhibitors. We will run the Phase 1 script synchronously and ensure it is optimized enough to finish well within this limit to prevent GNOME from forcefully killing the cleanup process mid-execution.
3. **No Root Privileges Required:** The Phase 1 backend script (`zerotrace.sh`) explicitly checks ownership and only targets user-owned files. Therefore, the background listener and the script can safely run entirely in user-space without requiring `sudo` or `polkit` configurations, ensuring a seamless UX.
