#!/usr/bin/env python3
import sys
import os
import subprocess
import sqlite3
import datetime
import re
import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GLib, Gio, Pango

# ANSI escape sequence regex
ANSI_ESCAPE = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')

# DB Setup
DATA_DIR = os.path.expanduser("~/.local/share/zerotrace")
os.makedirs(DATA_DIR, exist_ok=True)
DB_PATH = os.path.join(DATA_DIR, "logs.db")

def init_db():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS cleanups (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp DATETIME,
            status TEXT,
            full_output TEXT
        )
    ''')
    conn.commit()
    conn.close()

def save_log(status, full_output):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO cleanups (timestamp, status, full_output) VALUES (?, ?, ?)",
        (datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"), status, full_output)
    )
    conn.commit()
    conn.close()


class LogsDialog(Gtk.Dialog):
    def __init__(self, parent):
        super().__init__(title="Cleanup History", transient_for=parent, flags=0)
        self.add_buttons(Gtk.STOCK_CLOSE, Gtk.ResponseType.CLOSE)
        self.set_default_size(500, 400)

        # Scrolled window
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        self.get_content_area().pack_start(scrolled, True, True, 0)

        # TreeView for logs
        self.liststore = Gtk.ListStore(int, str, str)
        treeview = Gtk.TreeView(model=self.liststore)

        for i, column_title in enumerate(["ID", "Timestamp", "Status"]):
            renderer = Gtk.CellRendererText()
            column = Gtk.TreeViewColumn(column_title, renderer, text=i)
            treeview.append_column(column)

        scrolled.add(treeview)
        
        self.load_logs()
        self.show_all()

    def load_logs(self):
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT id, timestamp, status FROM cleanups ORDER BY id DESC")
        for row in cursor.fetchall():
            self.liststore.append(list(row))
        conn.close()


class SettingsDialog(Gtk.Dialog):
    def __init__(self, parent):
        super().__init__(title="Settings", transient_for=parent, flags=0)
        self.parent_win = parent
        self.add_buttons(Gtk.STOCK_CLOSE, Gtk.ResponseType.CLOSE)
        self.set_default_size(300, 150)

        box = self.get_content_area()
        box.set_spacing(10)
        box.set_border_width(10)

        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        label = Gtk.Label(label="Dry Run Mode (Simulate cleanup):")
        self.switch = Gtk.Switch()
        self.switch.set_active(self.parent_win.dry_run_enabled)
        self.switch.connect("notify::active", self.on_switch_activated)

        hbox.pack_start(label, False, False, 0)
        hbox.pack_end(self.switch, False, False, 0)
        
        box.pack_start(hbox, False, False, 0)
        self.show_all()

    def on_switch_activated(self, switch, gparam):
        self.parent_win.dry_run_enabled = switch.get_active()


class ZeroTraceDialog(Gtk.Window):
    def __init__(self):
        super().__init__(title="ZeroTrace OS")
        self.set_default_size(600, 600)
        self.set_position(Gtk.WindowPosition.CENTER)
        
        # State
        self.countdown_seconds = 10
        self.timer_id = None
        self.dry_run_enabled = False
        self.full_output_log = ""
        self.process = None

        # Setup HeaderBar
        header = Gtk.HeaderBar()
        header.set_show_close_button(True)
        header.props.title = "ZeroTrace System Cleaner"
        self.set_titlebar(header)

        # Settings Button
        settings_btn = Gtk.Button()
        icon = Gio.ThemedIcon(name="emblem-system-symbolic")
        image = Gtk.Image.new_from_gicon(icon, Gtk.IconSize.BUTTON)
        settings_btn.add(image)
        settings_btn.connect("clicked", self.on_settings_clicked)
        header.pack_end(settings_btn)

        # Logs Button
        logs_btn = Gtk.Button()
        icon = Gio.ThemedIcon(name="view-list-symbolic")
        image = Gtk.Image.new_from_gicon(icon, Gtk.IconSize.BUTTON)
        logs_btn.add(image)
        logs_btn.connect("clicked", self.on_logs_clicked)
        header.pack_end(logs_btn)

        # Main Layout
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=15)
        vbox.set_border_width(20)
        self.add(vbox)

        title_label = Gtk.Label()
        title_label.set_markup("<b><big>Your session is ending</big></b>")
        title_label.set_halign(Gtk.Align.START)
        vbox.pack_start(title_label, False, False, 0)

        desc_label = Gtk.Label(label="To maintain privacy on this shared machine, ZeroTrace will now securely erase temporary files, browser cache, and cookies.")
        desc_label.set_line_wrap(True)
        desc_label.set_halign(Gtk.Align.START)
        vbox.pack_start(desc_label, False, False, 0)

        # Button Box
        self.btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.btn_box.set_halign(Gtk.Align.END)
        vbox.pack_start(self.btn_box, False, False, 10)

        self.btn_skip = Gtk.Button(label="Skip")
        self.btn_skip.connect("clicked", self.on_skip_clicked)
        self.btn_box.pack_start(self.btn_skip, False, False, 0)

        self.btn_clean = Gtk.Button(label=f"Clean Now ({self.countdown_seconds})")
        self.btn_clean.connect("clicked", self.on_clean_clicked)
        context = self.btn_clean.get_style_context()
        context.add_class("destructive-action")
        self.btn_box.pack_start(self.btn_clean, False, False, 0)

        # Output Expander
        self.expander = Gtk.Expander(label="Show Details")
        vbox.pack_start(self.expander, True, True, 0)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_min_content_height(300)
        self.expander.add(scrolled)

        self.textview = Gtk.TextView()
        self.textview.set_editable(False)
        self.textview.set_cursor_visible(False)
        self.textview.set_monospace(True)
        # Small font using CSS
        css_provider = Gtk.CssProvider()
        css_provider.load_from_data(b"textview { font-family: monospace; font-size: 9pt; }")
        context = self.textview.get_style_context()
        context.add_provider(css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        scrolled.add(self.textview)
        
        self.textbuffer = self.textview.get_buffer()

        self.timer_id = GLib.timeout_add_seconds(1, self.on_timer_tick)

    def on_settings_clicked(self, widget):
        dialog = SettingsDialog(self)
        dialog.run()
        dialog.destroy()

    def on_logs_clicked(self, widget):
        dialog = LogsDialog(self)
        dialog.run()
        dialog.destroy()

    def on_timer_tick(self):
        self.countdown_seconds -= 1
        
        if self.countdown_seconds <= 0:
            self.start_cleanup()
            return False 
            
        self.btn_clean.set_label(f"Clean Now ({self.countdown_seconds})")
        return True 

    def on_skip_clicked(self, widget):
        if self.timer_id:
            GLib.source_remove(self.timer_id)
        Gtk.main_quit()

    def on_clean_clicked(self, widget):
        if self.timer_id:
            GLib.source_remove(self.timer_id)
        self.start_cleanup()

    def start_cleanup(self):
        self.btn_clean.set_label("Cleaning...")
        self.btn_clean.set_sensitive(False)
        self.btn_skip.set_sensitive(False)
        self.expander.set_expanded(True)
        
        script_dir = os.path.dirname(os.path.realpath(__file__))
        script_path = os.path.join(script_dir, "zerotrace.sh")
        
        cmd = [script_path]
        if self.dry_run_enabled:
            cmd.append("--dry-run")
            
        if not os.path.exists(script_path):
            self.append_output(f"Error: {script_path} not found.\n")
            save_log("Failed (Script not found)", "Error: Script not found.")
            self.finish_cleanup()
            return

        try:
            self.process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                bufsize=1,
                universal_newlines=True
            )
            
            # Watch the stdout pipe asynchronously
            GLib.io_add_watch(self.process.stdout, GLib.IO_IN, self.read_output)
            GLib.child_watch_add(self.process.pid, self.on_process_exit)
            
        except Exception as e:
            self.append_output(f"Failed to start cleanup: {e}\n")
            save_log("Failed", str(e))
            self.finish_cleanup()

    def read_output(self, fd, condition):
        if condition == GLib.IO_IN:
            line = fd.readline()
            if line:
                clean_line = ANSI_ESCAPE.sub('', line)
                self.full_output_log += clean_line
                self.append_output(clean_line)
                return True # Continue watching
        return False

    def on_process_exit(self, pid, status):
        # GLib automatically reaps the child process, so we use the provided 'status' argument
        exit_code = os.WEXITSTATUS(status) if os.WIFEXITED(status) else -1
        final_status = "Success" if exit_code == 0 else "Failed"
        save_log(final_status, self.full_output_log)
        self.finish_cleanup()

    def append_output(self, text):
        end_iter = self.textbuffer.get_end_iter()
        self.textbuffer.insert(end_iter, text)
        
        # Scroll to bottom
        mark = self.textbuffer.create_mark(None, self.textbuffer.get_end_iter(), False)
        self.textview.scroll_to_mark(mark, 0.05, True, 0.0, 1.0)

    def finish_cleanup(self):
        self.btn_clean.set_label("Finished")
        self.btn_skip.set_label("Close")
        self.btn_skip.set_sensitive(True)
        
        # Override skip button to just close since we're done
        self.btn_skip.disconnect_by_func(self.on_skip_clicked)
        self.btn_skip.connect("clicked", lambda x: Gtk.main_quit())

if __name__ == "__main__":
    init_db()
    win = ZeroTraceDialog()
    win.connect("destroy", Gtk.main_quit)
    win.show_all()
    Gtk.main()
