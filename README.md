# macOS Memory Warning (`mac-memory-warning`)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](https://www.apple.com/macos/)
[![Python](https://img.shields.io/badge/python-3.8+-blue.svg)](https://www.python.org/downloads/)

A lightweight background monitor and **macOS Menu Bar (tray) app** that alerts you with native system notifications whenever any process exceeds a configurable RAM threshold (e.g., `500 MB`, `1 GB`, `2 GB`).

---

## Features

- 🖥️ **macOS `.app` Bundle & Menu Bar (Tray) Mini-UI**:
  - Ready-to-use **`Memory Warning.app`** — double-click to launch the daemon in the menu bar.
  - Sits quietly in the top status bar as `💾` (or `⚠️ 1.4 GB` when high memory is detected).
  - Clean shutdown: clicking **Quit** or terminating the process completely stops the background daemon.
  - Interactive controls: change threshold (`500MB`, `1GB`, `1.5GB`, `2GB` or custom), toggle notifications, toggle sound, change interval (`5s`–`60s`).
  - Submenu showing live **Top 5 Memory Consumers**.
  - Remembers your settings in `~/.config/memory-warning/config.json`.
- 🌐 **Multilingual (EN / RU)**:
  - Automatically adapts to system language (`AppleLanguages` / `LANG`), with manual toggle in menu bar or CLI.
- 🔔 **Native macOS Notifications**:
  - Notification Center alerts with audible sound via AppleScript (`osascript`).
  - Cooldown protection against notification spam (default: once every 5 minutes per process).
- ⚙️ **Dual Mode**:
  - **Menu Bar App** (`Memory Warning.app` / `menubar.py`) for visual tray usage.
  - **Headless CLI Daemon** (`memory_monitor.py` / `LaunchAgent`) for servers or background terminal usage.

---

## Quick Launch: Double-Click Executables

### 1. Native macOS App Bundle
Double-click **`Memory Warning.app`** in Finder!
- Launches the menu bar daemon without showing an empty Dock icon (`LSUIElement = true`).
- To close the daemon, click the `💾` icon in the menu bar and select **Quit** (или **Выход**).

### 2. Double-Click Command Script
Double-click **`run.command`** in Finder to launch the monitor directly in Terminal. Closing the Terminal window stops the daemon immediately.

---

## Installation & Setup

```bash
git clone https://github.com/yourusername/mac-memory-warning.git
cd mac-memory-warning

# Install requirements (rumps for status bar GUI & psutil for fast scanning)
pip install -r requirements.txt
```

To build or refresh the `.app` bundle at any time:
```bash
chmod +x build_app.sh
./build_app.sh
```

---

## Headless CLI Usage

If you prefer running without the menu bar icon:

```bash
# One-time memory check
python3 memory_monitor.py --threshold 1GB --once

# Foreground daemon
python3 memory_monitor.py --threshold 500MB --interval 10
```

---

## Background Autostart on Boot (macOS LaunchAgent)

To run silently on login:

```bash
chmod +x install_agent.sh uninstall_agent.sh
./install_agent.sh 1GB 15 auto
```

Uninstall:
```bash
./uninstall_agent.sh
```

---

## Running Tests

```bash
pip install -e ".[dev,gui]"
pytest
```

---

## Releasing New Versions

Releases are automatically built and published via GitHub Actions when a version tag is pushed:

```bash
# 1. Create and push a new git tag (e.g. v0.2.0)
git tag v0.2.0
git push origin v0.2.0
```

GitHub Actions will:
1. Run test suite across Python versions.
2. Build `Memory Warning.app` for macOS.
3. Package it into `Memory-Warning-v0.2.0-macos.zip`.
4. Create a new GitHub Release with release notes and attach the ready-to-run `.zip` asset.

You can also trigger a release build manually from the **Actions** tab on GitHub via **Run workflow** (`workflow_dispatch`).

---

## License

This project is licensed under the [MIT License](LICENSE).
