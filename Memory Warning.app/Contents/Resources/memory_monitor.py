#!/usr/bin/env python3
"""
macOS Process Memory Monitor (memory-warning)
Periodically monitors running processes and notifies the user via native macOS
alerts whenever a process exceeds a configurable memory threshold.
Supports multi-language notifications and console output (English & Russian).
"""

import argparse
import os
import re
import subprocess
import sys
import time
from typing import Dict, List, Optional, Set, Tuple

# Try importing psutil; if not available, a native 'ps' fallback is used.
try:
    import psutil
    HAS_PSUTIL = True
except ImportError:
    psutil = None
    HAS_PSUTIL = False

# Localization dictionary
TRANSLATIONS = {
    "en": {
        "notification_title": "High Memory Warning",
        "notification_body": "Memory usage: {mem} (Limit: {threshold})",
        "warn_console": "[{timestamp}] ⚠️ WARNING: '{name}' (PID: {pid}) is using {mem} (threshold: {threshold})",
        "header_title": "macOS Process Memory Monitor",
        "header_engine": "Engine:           {engine}",
        "header_threshold": "Memory Threshold: {threshold}",
        "header_interval": "Check Interval:   {interval}s",
        "header_cooldown": "Alert Cooldown:   {cooldown:.1f} minutes per process",
        "header_ignore": "Ignored list:     {ignored}",
        "header_lang": "Language:         {lang}",
        "started": "Monitoring started... Press Ctrl+C to stop.\n",
        "stopped": "\nMonitoring stopped by user.",
        "none_found": "No processes exceed the threshold of {threshold}.",
        "found_count": "\nFound {count} process(es) exceeding {threshold}.",
        "engine_psutil": "psutil",
        "engine_ps": "native ps (fallback)",
    },
    "ru": {
        "notification_title": "Предупреждение о памяти",
        "notification_body": "Использование памяти: {mem} (Лимит: {threshold})",
        "warn_console": "[{timestamp}] ⚠️ ВНИМАНИЕ: '{name}' (PID: {pid}) использует {mem} (лимит: {threshold})",
        "header_title": "Монитор оперативной памяти macOS",
        "header_engine": "Движок:           {engine}",
        "header_threshold": "Порог памяти:     {threshold}",
        "header_interval": "Интервал:         {interval} сек",
        "header_cooldown": "Кулдаун:          {cooldown:.1f} мин на процесс",
        "header_ignore": "Исключения:       {ignored}",
        "header_lang": "Язык:             {lang}",
        "started": "Мониторинг запущен... Нажмите Ctrl+C для остановки.\n",
        "stopped": "\nМониторинг остановлен пользователем.",
        "none_found": "Нет процессов, превышающих лимит {threshold}.",
        "found_count": "\nНайдено процессов, превышающих лимит {threshold}: {count}.",
        "engine_psutil": "psutil",
        "engine_ps": "системный ps (fallback)",
    },
}


def detect_system_language() -> str:
    """
    Detects the system language on macOS.
    Checks environment variables (LC_ALL, LANG) and macOS AppleLanguages preference.
    Defaults to 'en'.
    """
    for env_var in ("LC_ALL", "LC_MESSAGES", "LANG"):
        val = os.environ.get(env_var)
        if val:
            prefix = val.split("_")[0].split(".")[0].lower()
            if prefix in TRANSLATIONS:
                return prefix

    try:
        res = subprocess.run(
            ["defaults", "read", "-g", "AppleLanguages"],
            capture_output=True,
            text=True,
            check=False,
        )
        if res.stdout:
            match = re.search(r'"([a-zA-Z]{2})[-_]', res.stdout)
            if match:
                code = match.group(1).lower()
                if code in TRANSLATIONS:
                    return code
    except Exception:
        pass

    return "en"


def get_t(lang: str) -> Dict[str, str]:
    """Returns the translation dictionary for given language code."""
    return TRANSLATIONS.get(lang, TRANSLATIONS["en"])


def parse_size(size_str: str) -> float:
    """
    Parses human-readable size strings like '1GB', '1.5G', '500MB', '1024M', '2048KB'
    into bytes.
    """
    cleaned = size_str.strip().upper()
    match = re.match(r"^([0-9]+(?:\.[0-9]+)?)\s*([KMGTP]?B?)$", cleaned)
    if not match:
        raise argparse.ArgumentTypeError(
            f"Invalid memory size format: '{size_str}'. Example valid formats: 1GB, 500MB, 1.5G, 1024M."
        )

    val_str, unit = match.groups()
    val = float(val_str)

    units = {
        "": 1,
        "B": 1,
        "K": 1024,
        "KB": 1024,
        "M": 1024**2,
        "MB": 1024**2,
        "G": 1024**3,
        "GB": 1024**3,
        "T": 1024**4,
        "TB": 1024**4,
    }
    return val * units.get(unit, 1024**2)


def format_bytes(num_bytes: float) -> str:
    """Formats bytes into human-readable representation."""
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if abs(num_bytes) < 1024.0:
            return f"{num_bytes:3.1f} {unit}"
        num_bytes /= 1024.0
    return f"{num_bytes:.1f} PB"


def send_macos_notification(title: str, subtitle: str, message: str, sound: bool = True):
    """Triggers a native macOS notification via AppleScript."""
    def escape_as(text: str) -> str:
        return text.replace("\\", "\\\\").replace('"', '\\"')

    as_title = escape_as(title)
    as_subtitle = escape_as(subtitle)
    as_msg = escape_as(message)

    sound_clause = ' sound name "Ping"' if sound else ""
    script = (
        f'display notification "{as_msg}" with title "{as_title}" '
        f'subtitle "{as_subtitle}"{sound_clause}'
    )
    try:
        subprocess.run(["osascript", "-e", script], check=True, capture_output=True)
    except Exception as e:
        print(f"[ERROR] Failed to send macOS notification: {e}", file=sys.stderr)


def get_processes_psutil() -> List[Tuple[int, str, int]]:
    """Retrieves (pid, name, rss_bytes) using psutil."""
    procs = []
    for p in psutil.process_iter(["pid", "name", "memory_info"]):
        try:
            info = p.info
            mem_info = info.get("memory_info")
            if mem_info:
                procs.append((info["pid"], info.get("name") or "Unknown", mem_info.rss))
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            continue
    return procs


def get_processes_native_ps() -> List[Tuple[int, str, int]]:
    """
    Fallback: retrieves (pid, name, rss_bytes) using macOS native 'ps' command.
    'ps -ax -o pid=,rss=,comm=' returns PID, RSS (in KB), and command/process name.
    """
    procs = []
    try:
        output = subprocess.check_output(
            ["ps", "-ax", "-o", "pid=,rss=,comm="],
            universal_newlines=True,
            stderr=subprocess.DEVNULL,
        )
        for line in output.strip().split("\n"):
            parts = line.strip().split(None, 2)
            if len(parts) >= 3:
                pid_str, rss_kb_str, comm = parts[0], parts[1], parts[2]
                try:
                    pid = int(pid_str)
                    rss_bytes = int(rss_kb_str) * 1024
                    name = os.path.basename(comm)
                    procs.append((pid, name, rss_bytes))
                except ValueError:
                    continue
    except Exception as e:
        print(f"[ERROR] Native 'ps' scan failed: {e}", file=sys.stderr)
    return procs


def scan_processes() -> List[Tuple[int, str, int]]:
    """Scan all running processes using either psutil or native ps."""
    if HAS_PSUTIL:
        return get_processes_psutil()
    return get_processes_native_ps()


def monitor_loop(
    threshold_bytes: float,
    interval: float,
    cooldown_seconds: float,
    sound: bool,
    ignore_list: Set[str],
    lang: str = "auto",
    once: bool = False,
):
    selected_lang = detect_system_language() if lang == "auto" else lang
    t = get_t(selected_lang)

    notified_at: Dict[int, float] = {}

    print("=" * 60)
    print(t["header_title"])
    engine_name = t["engine_psutil"] if HAS_PSUTIL else t["engine_ps"]
    print(t["header_engine"].format(engine=engine_name))
    print(t["header_threshold"].format(threshold=format_bytes(threshold_bytes)))
    print(t["header_interval"].format(interval=interval))
    print(t["header_cooldown"].format(cooldown=cooldown_seconds / 60))
    print(t["header_lang"].format(lang=f"{selected_lang} ({'auto-detected' if lang == 'auto' else 'manual'})"))
    if ignore_list:
        print(t["header_ignore"].format(ignored=", ".join(sorted(ignore_list))))
    print("=" * 60)
    print(t["started"])

    try:
        while True:
            current_time = time.time()
            all_procs = scan_processes()

            live_pids = {p[0] for p in all_procs}
            dead_pids = [pid for pid in notified_at if pid not in live_pids]
            for pid in dead_pids:
                del notified_at[pid]

            violators = []
            for pid, name, rss in all_procs:
                if name.lower() in ignore_list or any(
                    ign in name.lower() for ign in ignore_list
                ):
                    continue
                if rss >= threshold_bytes:
                    violators.append((pid, name, rss))

            violators.sort(key=lambda x: x[2], reverse=True)

            for pid, name, rss in violators:
                last_time = notified_at.get(pid, 0)
                if current_time - last_time >= cooldown_seconds:
                    notified_at[pid] = current_time
                    formatted_mem = format_bytes(rss)
                    threshold_formatted = format_bytes(threshold_bytes)
                    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")

                    print(
                        t["warn_console"].format(
                            timestamp=timestamp,
                            name=name,
                            pid=pid,
                            mem=formatted_mem,
                            threshold=threshold_formatted,
                        )
                    )

                    notif_body = t["notification_body"].format(
                        mem=formatted_mem,
                        threshold=threshold_formatted,
                    )
                    send_macos_notification(
                        title=t["notification_title"],
                        subtitle=f"{name} (PID: {pid})",
                        message=notif_body,
                        sound=sound,
                    )

            if once:
                threshold_formatted = format_bytes(threshold_bytes)
                if not violators:
                    print(t["none_found"].format(threshold=threshold_formatted))
                else:
                    print(
                        t["found_count"].format(
                            count=len(violators), threshold=threshold_formatted
                        )
                    )
                break

            time.sleep(interval)

    except KeyboardInterrupt:
        print(t["stopped"])


def main():
    parser = argparse.ArgumentParser(
        description="Monitor macOS processes and alert when RAM exceeds a threshold."
    )
    parser.add_argument(
        "-t",
        "--threshold",
        default="1GB",
        help="Memory threshold for notification (e.g., 1GB, 1.5G, 750MB, 1024M). Default: 1GB",
    )
    parser.add_argument(
        "-i",
        "--interval",
        type=float,
        default=15.0,
        help="Polling interval in seconds. Default: 15",
    )
    parser.add_argument(
        "-c",
        "--cooldown",
        type=float,
        default=300.0,
        help="Cooldown period in seconds before repeating alert for the same process. Default: 300 (5 min)",
    )
    parser.add_argument(
        "-l",
        "--lang",
        choices=["auto", "en", "ru"],
        default="auto",
        help="Notification & interface language: 'auto' (detect from system), 'en', or 'ru'. Default: auto",
    )
    parser.add_argument(
        "--no-sound",
        action="store_true",
        help="Mute notification sound.",
    )
    parser.add_argument(
        "--ignore",
        nargs="*",
        default=[],
        help="Names or substrings of processes to ignore (case-insensitive).",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="Run a single check and exit (useful for testing or cron).",
    )

    args = parser.parse_args()

    threshold_bytes = parse_size(args.threshold)
    ignore_set = {item.strip().lower() for item in args.ignore if item.strip()}

    monitor_loop(
        threshold_bytes=threshold_bytes,
        interval=args.interval,
        cooldown_seconds=args.cooldown,
        sound=not args.no_sound,
        ignore_list=ignore_set,
        lang=args.lang,
        once=args.once,
    )


if __name__ == "__main__":
    main()

