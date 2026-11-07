#!/usr/bin/env python3
"""
macOS Menu Bar App for Process Memory Monitor (mac-memory-warning)
Runs in the macOS status bar (top menu bar / tray) allowing interactive
configuration of thresholds, notification alerts, sounds, and intervals.
"""

import json
import os
import sys
import time
from pathlib import Path
from typing import Dict, Any

try:
    import rumps
except ImportError:
    print(
        "[ERROR] 'rumps' is required to run the menu bar app.\n"
        "Please install it using:\n"
        "    pip install rumps\n"
        "or install all optional dependencies with:\n"
        "    pip install .[gui]",
        file=sys.stderr,
    )
    sys.exit(1)

from memory_monitor import (
    HAS_PSUTIL,
    TRANSLATIONS,
    detect_system_language,
    format_bytes,
    get_t,
    parse_size,
    scan_processes,
    send_macos_notification,
)

CONFIG_DIR = Path.home() / ".config" / "memory-warning"
CONFIG_FILE = CONFIG_DIR / "config.json"

DEFAULT_CONFIG: Dict[str, Any] = {
    "threshold": "1GB",
    "interval": 15,
    "cooldown": 300,
    "sound": True,
    "notifications_enabled": True,
    "lang": "auto",
    "show_top_in_title": False,
}


def load_config() -> Dict[str, Any]:
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                cfg = DEFAULT_CONFIG.copy()
                cfg.update(data)
                return cfg
        except Exception:
            pass
    return DEFAULT_CONFIG.copy()


def save_config(cfg: Dict[str, Any]):
    try:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2, ensure_ascii=False)
    except Exception as e:
        print(f"[ERROR] Failed to save config: {e}", file=sys.stderr)


class MemoryWarningApp(rumps.App):
    def __init__(self):
        super().__init__("💾", quit_button=None)
        self.cfg = load_config()
        self.notified_at: Dict[int, float] = {}

        # Resolve active language
        self.active_lang = (
            detect_system_language()
            if self.cfg["lang"] == "auto"
            else self.cfg["lang"]
        )

        # Threshold presets in bytes
        self.threshold_options = ["500MB", "1GB", "1.5GB", "2GB", "3GB", "4GB"]
        self.interval_options = [5, 10, 15, 30, 60]

        # Build initial menu
        self.rebuild_menu()

        # Start timer for background checking
        self.timer = rumps.Timer(self.check_memory, self.cfg["interval"])
        self.timer.start()

    def t(self, key: str, **kwargs) -> str:
        """Helper to get translated string."""
        lang_dict = get_t(self.active_lang)
        text = lang_dict.get(key, TRANSLATIONS["en"].get(key, key))
        if kwargs:
            return text.format(**kwargs)
        return text

    def rebuild_menu(self):
        """Builds or refreshes the menubar drop-down items."""
        is_ru = self.active_lang == "ru"
        current_thresh = self.cfg["threshold"]
        current_interval = self.cfg["interval"]

        self.menu.clear()

        # Top processes section (will be populated dynamically)
        status_title = (
            f"⚡ Порог: {current_thresh}" if is_ru else f"⚡ Threshold: {current_thresh}"
        )
        self.menu.add(rumps.MenuItem(status_title))
        self.menu.add(rumps.separator)

        # --- Submenu: Memory Threshold ---
        thresh_menu_title = "Порог памяти" if is_ru else "Memory Threshold"
        thresh_menu = rumps.MenuItem(thresh_menu_title)
        for opt in self.threshold_options:
            item = rumps.MenuItem(opt, callback=self.on_select_threshold)
            item.state = 1 if opt.upper() == current_thresh.upper() else 0
            thresh_menu.add(item)

        custom_title = "Свой порог..." if is_ru else "Custom threshold..."
        thresh_menu.add(rumps.separator)
        thresh_menu.add(rumps.MenuItem(custom_title, callback=self.on_custom_threshold))
        self.menu.add(thresh_menu)

        # --- Submenu: Check Interval ---
        interval_menu_title = "Интервал проверки" if is_ru else "Check Interval"
        interval_menu = rumps.MenuItem(interval_menu_title)
        for sec in self.interval_options:
            label = f"{sec} сек" if is_ru else f"{sec} seconds"
            item = rumps.MenuItem(label, callback=self.on_select_interval)
            item._seconds = sec
            item.state = 1 if sec == current_interval else 0
            interval_menu.add(item)
        self.menu.add(interval_menu)

        # --- Notifications Toggle ---
        notif_title = "Оповещения" if is_ru else "Notifications"
        notif_item = rumps.MenuItem(notif_title, callback=self.on_toggle_notifications)
        notif_item.state = 1 if self.cfg["notifications_enabled"] else 0
        self.menu.add(notif_item)

        # --- Sound Toggle ---
        sound_title = "Звуковой сигнал" if is_ru else "Alert Sound"
        sound_item = rumps.MenuItem(sound_title, callback=self.on_toggle_sound)
        sound_item.state = 1 if self.cfg["sound"] else 0
        self.menu.add(sound_item)

        self.menu.add(rumps.separator)

        # --- Top Processes Submenu ---
        top_procs_title = "Топ процессов по памяти" if is_ru else "Top Memory Consumers"
        self.top_menu = rumps.MenuItem(top_procs_title)
        self.top_menu.add(rumps.MenuItem("Сканирование..." if is_ru else "Scanning..."))
        self.menu.add(self.top_menu)

        # --- Submenu: Language ---
        lang_menu_title = "Язык / Language"
        lang_menu = rumps.MenuItem(lang_menu_title)

        auto_item = rumps.MenuItem("Авто (Система) / Auto (System)", callback=self.on_select_lang)
        auto_item._lang_val = "auto"
        auto_item.state = 1 if self.cfg["lang"] == "auto" else 0
        lang_menu.add(auto_item)

        en_item = rumps.MenuItem("English", callback=self.on_select_lang)
        en_item._lang_val = "en"
        en_item.state = 1 if self.cfg["lang"] == "en" else 0
        lang_menu.add(en_item)

        ru_item = rumps.MenuItem("Русский", callback=self.on_select_lang)
        ru_item._lang_val = "ru"
        ru_item.state = 1 if self.cfg["lang"] == "ru" else 0
        lang_menu.add(ru_item)

        self.menu.add(lang_menu)

        self.menu.add(rumps.separator)

        # Quit
        quit_title = "Выход" if is_ru else "Quit"
        self.menu.add(rumps.MenuItem(quit_title, callback=rumps.quit_application))

    def on_select_threshold(self, sender):
        self.cfg["threshold"] = sender.title
        save_config(self.cfg)
        self.rebuild_menu()

    def on_custom_threshold(self, _):
        is_ru = self.active_lang == "ru"
        msg = (
            "Введите лимит памяти (например: 750MB, 1.2GB, 2500M):"
            if is_ru
            else "Enter memory limit (e.g. 750MB, 1.2GB, 2500M):"
        )
        title = "Настройка порога" if is_ru else "Custom Threshold"
        window = rumps.Window(msg, title, default_text=self.cfg["threshold"])
        response = window.run()
        if response.clicked:
            text = response.text.strip()
            try:
                parse_size(text)  # validate
                self.cfg["threshold"] = text
                save_config(self.cfg)
                self.rebuild_menu()
            except Exception:
                err_msg = (
                    "Неверный формат. Примеры: 500MB, 1GB, 1.5G"
                    if is_ru
                    else "Invalid format. Examples: 500MB, 1GB, 1.5G"
                )
                rumps.alert("Error", err_msg)

    def on_select_interval(self, sender):
        sec = getattr(sender, "_seconds", 15)
        self.cfg["interval"] = sec
        save_config(self.cfg)
        self.timer.stop()
        self.timer.interval = sec
        self.timer.start()
        self.rebuild_menu()

    def on_toggle_notifications(self, sender):
        self.cfg["notifications_enabled"] = not self.cfg["notifications_enabled"]
        save_config(self.cfg)
        sender.state = 1 if self.cfg["notifications_enabled"] else 0

    def on_toggle_sound(self, sender):
        self.cfg["sound"] = not self.cfg["sound"]
        save_config(self.cfg)
        sender.state = 1 if self.cfg["sound"] else 0

    def on_select_lang(self, sender):
        val = getattr(sender, "_lang_val", "auto")
        self.cfg["lang"] = val
        self.active_lang = detect_system_language() if val == "auto" else val
        save_config(self.cfg)
        self.rebuild_menu()

    def check_memory(self, _):
        """Background routine executed on each timer tick."""
        try:
            threshold_bytes = parse_size(self.cfg["threshold"])
        except Exception:
            threshold_bytes = 1024**3

        all_procs = scan_processes()
        current_time = time.time()

        # Clean up dead PIDs
        live_pids = {p[0] for p in all_procs}
        for pid in list(self.notified_at.keys()):
            if pid not in live_pids:
                del self.notified_at[pid]

        # Sort all by RSS descending
        all_procs.sort(key=lambda x: x[2], reverse=True)

        # Update Top Processes submenu
        self.update_top_processes_menu(all_procs[:5])

        # Filter violators
        violators = [p for p in all_procs if p[2] >= threshold_bytes]

        # Update menubar icon if there are violators
        if violators:
            self.title = f"⚠️ {format_bytes(violators[0][2])}"
        else:
            self.title = "💾"

        if not self.cfg["notifications_enabled"]:
            return

        cooldown_sec = self.cfg.get("cooldown", 300)
        for pid, name, rss in violators:
            last_time = self.notified_at.get(pid, 0)
            if current_time - last_time >= cooldown_sec:
                self.notified_at[pid] = current_time
                formatted_mem = format_bytes(rss)
                formatted_thresh = format_bytes(threshold_bytes)

                notif_title = self.t("notification_title")
                notif_body = self.t(
                    "notification_body", mem=formatted_mem, threshold=formatted_thresh
                )

                send_macos_notification(
                    title=notif_title,
                    subtitle=f"{name} (PID: {pid})",
                    message=notif_body,
                    sound=self.cfg["sound"],
                )

    def update_top_processes_menu(self, top_list):
        """Updates the top processes submenu items."""
        self.top_menu.clear()
        if not top_list:
            self.top_menu.add(rumps.MenuItem("Нет данных" if self.active_lang == "ru" else "No data"))
            return

        for pid, name, rss in top_list:
            label = f"{name[:18]} (PID {pid}): {format_bytes(rss)}"
            self.top_menu.add(rumps.MenuItem(label))


def main():
    app = MemoryWarningApp()
    app.run()


if __name__ == "__main__":
    main()
