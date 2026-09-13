#!/usr/bin/env python3
"""
ZeroTrace Phase 3 — D-Bus Session Listener

Runs as a background daemon in the user's GNOME session. Detects logout
and switch-user events via D-Bus, then launches the Phase 2 GUI so the
user can clean (or skip) before the session ends.

Logout:  org.gnome.SessionManager → QueryEndSession signal
Switch:  org.freedesktop.login1.Manager → SessionNew signal
"""

import os
import sys
import subprocess
import signal

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gio

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
GUI_PATH = os.path.join(SCRIPT_DIR, "zerotrace-gui.py")

SESSION_MANAGER_NAME = "org.gnome.SessionManager"
SESSION_MANAGER_PATH = "/org/gnome/SessionManager"
SESSION_MANAGER_IFACE = "org.gnome.SessionManager"
CLIENT_PRIVATE_IFACE = "org.gnome.SessionManager.ClientPrivate"

LOGIN1_NAME = "org.freedesktop.login1"
LOGIN1_PATH = "/org/freedesktop/login1"
LOGIN1_MANAGER_IFACE = "org.freedesktop.login1.Manager"


class ZeroTraceListener:
    def __init__(self):
        self.loop = GLib.MainLoop()
        self.session_bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.system_bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        self.client_path = None
        self.gui_running = False
        self.current_uid = os.getuid()

    def start(self):
        self._register_with_session_manager()
        self._watch_switch_user()

        signal.signal(signal.SIGTERM, lambda *_: self.loop.quit())
        signal.signal(signal.SIGINT, lambda *_: self.loop.quit())

        print(f"[zerotrace-listener] running (pid {os.getpid()})")
        self.loop.run()

    # ── Logout: GNOME SessionManager ──────────────────────────────

    def _register_with_session_manager(self):
        try:
            result = self.session_bus.call_sync(
                SESSION_MANAGER_NAME,
                SESSION_MANAGER_PATH,
                SESSION_MANAGER_IFACE,
                "RegisterClient",
                GLib.Variant("(ss)", ("zerotrace", "")),
                GLib.VariantType("(o)"),
                Gio.DBusCallFlags.NONE,
                -1,
                None,
            )
            self.client_path = result.unpack()[0]
            print(f"[zerotrace-listener] registered as session client: {self.client_path}")

            self.session_bus.signal_subscribe(
                SESSION_MANAGER_NAME,
                CLIENT_PRIVATE_IFACE,
                "QueryEndSession",
                self.client_path,
                None,
                Gio.DBusSignalFlags.NONE,
                self._on_query_end_session,
            )

            self.session_bus.signal_subscribe(
                SESSION_MANAGER_NAME,
                CLIENT_PRIVATE_IFACE,
                "EndSession",
                self.client_path,
                None,
                Gio.DBusSignalFlags.NONE,
                self._on_end_session,
            )

            self.session_bus.signal_subscribe(
                SESSION_MANAGER_NAME,
                CLIENT_PRIVATE_IFACE,
                "Stop",
                self.client_path,
                None,
                Gio.DBusSignalFlags.NONE,
                self._on_stop,
            )

        except Exception as e:
            print(f"[zerotrace-listener] could not register with session manager: {e}")
            print("[zerotrace-listener] logout detection will not work")

    def _on_query_end_session(self, connection, sender, path, iface, signal_name, params):
        print("[zerotrace-listener] QueryEndSession received — launching GUI")
        self._launch_gui_and_wait()
        self._end_session_response(is_ok=True, reason="")

    def _on_end_session(self, connection, sender, path, iface, signal_name, params):
        print("[zerotrace-listener] EndSession received")
        self._end_session_response(is_ok=True, reason="")

    def _on_stop(self, connection, sender, path, iface, signal_name, params):
        print("[zerotrace-listener] Stop received — exiting")
        self.loop.quit()

    def _end_session_response(self, is_ok, reason):
        if not self.client_path:
            return
        try:
            self.session_bus.call_sync(
                SESSION_MANAGER_NAME,
                self.client_path,
                CLIENT_PRIVATE_IFACE,
                "EndSessionResponse",
                GLib.Variant("(bs)", (is_ok, reason)),
                None,
                Gio.DBusCallFlags.NONE,
                -1,
                None,
            )
        except Exception as e:
            print(f"[zerotrace-listener] EndSessionResponse failed: {e}")

    # ── Switch-user: systemd-logind ───────────────────────────────

    def _watch_switch_user(self):
        try:
            self.system_bus.signal_subscribe(
                LOGIN1_NAME,
                LOGIN1_MANAGER_IFACE,
                "SessionNew",
                LOGIN1_PATH,
                None,
                Gio.DBusSignalFlags.NONE,
                self._on_session_new,
            )
            print("[zerotrace-listener] watching logind for switch-user events")
        except Exception as e:
            print(f"[zerotrace-listener] could not watch logind: {e}")

    def _on_session_new(self, connection, sender, path, iface, signal_name, params):
        session_id, session_path = params.unpack()
        try:
            result = self.system_bus.call_sync(
                LOGIN1_NAME,
                session_path,
                "org.freedesktop.DBus.Properties",
                "Get",
                GLib.Variant("(ss)", ("org.freedesktop.login1.Session", "User")),
                GLib.VariantType("(v)"),
                Gio.DBusCallFlags.NONE,
                -1,
                None,
            )
            uid = result.unpack()[0].unpack()[0]
            if uid != self.current_uid:
                print(f"[zerotrace-listener] switch-user detected (new uid {uid}) — launching GUI")
                self._launch_gui_and_wait()
        except Exception as e:
            print(f"[zerotrace-listener] could not inspect new session: {e}")

    # ── Launch GUI ────────────────────────────────────────────────

    def _launch_gui_and_wait(self):
        if self.gui_running:
            print("[zerotrace-listener] GUI already running, skipping")
            return

        if not os.path.exists(GUI_PATH):
            print(f"[zerotrace-listener] GUI not found at {GUI_PATH}")
            return

        self.gui_running = True
        try:
            proc = subprocess.run(
                ["python3", GUI_PATH],
                timeout=55,
            )
            print(f"[zerotrace-listener] GUI exited with code {proc.returncode}")
        except subprocess.TimeoutExpired:
            print("[zerotrace-listener] GUI timed out (55s limit)")
        except Exception as e:
            print(f"[zerotrace-listener] failed to launch GUI: {e}")
        finally:
            self.gui_running = False


if __name__ == "__main__":
    listener = ZeroTraceListener()
    listener.start()
