# Project Plan: macOS Process Memory Monitor (`memory-warning`)

## 1. Overview & Objective
A lightweight utility for macOS that periodically monitors running processes and alerts the user whenever any process exceeds a configurable RAM threshold (e.g., > 1 GB).

---

## 2. Key Requirements
- **macOS Native Compatibility**: Efficient process & memory inspection on Apple Silicon & Intel macOS.
- **Configurable Parameters**:
  - Memory threshold (e.g., `--threshold 1GB`, `-t 1024MB`, or numeric value in GB/MB).
  - Monitoring interval (e.g., `--interval 10s`, default: every 10–30 seconds).
  - Cooldown / Debounce period per process (to avoid repeatedly spamming alerts for the same PID).
  - Whitelist / Ignore list (optional ignore for known heavy processes like IDEs, VMs, or specific system daemons).
- **User Alert Mechanisms**:
  - Native macOS Notification Center alert (via AppleScript / `osascript` or `terminal-notifier` / Swift UserNotifications).
  - Optional audible bell / system alert sound.
  - Formatted terminal/log output with timestamp, process name, PID, and exact memory usage.
- **Execution Modes**:
  - Interactive CLI / foreground daemon.
  - Background service (macOS `LaunchAgent` `.plist` to run silently on login).

---

## 3. Technology Stack Options

### Option A: Python CLI Daemon (Recommended for Simplicity & Flexibility)
- **Runtime**: Python 3 (standard on macOS or virtual environment).
- **Core Libraries**:
  - `psutil` (fast, cross-architecture process scanning with RSS memory extraction) or native `ps` parsing as a fallback with zero external dependencies.
  - `subprocess` with `osascript` for native macOS notifications.
  - `argparse` for CLI options and configuration.
- **Pros**: Quick to inspect, easy to modify, cross-version compatible, zero build step.

### Option B: Native Swift / Menubar App
- **Runtime**: Swift (compiled binary or menubar app).
- **Core Frameworks**: `AppKit` (NSWorkspace, NSApplication), `UserNotifications`.
- **Pros**: True native binary, menubar icon showing top memory consumer, low resource footprint.

---

## 4. Implementation Steps

### Phase 1: Core Monitoring Engine
- [ ] Determine memory metric: Resident Set Size (RSS) is the standard indicator of actual physical RAM held.
- [ ] Implement process scanner function to iterate running processes and retrieve `(pid, name, rss_memory)`.
- [ ] Filter out processes exceeding the configured threshold.
- [ ] Sort by memory usage descending.

### Phase 2: Alerting & Debounce Mechanism
- [ ] Implement macOS notification trigger:
  ```bash
  osascript -e 'display notification "Process <name> (PID: <pid>) is using <mem> MB RAM" with title "Memory Warning" sound name "Ping"'
  ```
- [ ] Implement notification throttling/cooldown dictionary `{pid: last_notified_timestamp}` to ensure an alert is sent at most once per cooldown window (e.g., every 5 minutes unless memory grows significantly).

### Phase 3: CLI & Configuration
- [ ] Add command-line flags:
  - `-t, --threshold`: Memory limit (e.g., `1GB`, `1500MB`).
  - `-i, --interval`: Polling interval in seconds (default: `15`).
  - `-c, --cooldown`: Cooldown interval in minutes before re-notifying for the same process (default: `5`).
  - `--sound`: Enable/disable notification sound.
  - `--ignore`: List of process names or regexes to ignore.
- [ ] Add config file support (`config.json` or `.env`) for persistent settings.

### Phase 4: Packaging & LaunchAgent (Autostart)
- [ ] Create a `LaunchAgent` generator (`~/Library/LaunchAgents/com.user.memorywarning.plist`) so it can start automatically in the background on system boot.
- [ ] Provide commands to install (`launchctl load`) and uninstall (`launchctl unload`) the background service.

---

## 5. File Structure
```text
memory-warning/
├── plan.md              # Project plan & specification
├── memory_monitor.py    # Main monitoring daemon script
├── requirements.txt     # Dependencies (e.g. psutil)
├── config.example.json  # Optional configuration template
├── install_agent.sh     # Script to configure & start LaunchAgent
└── README.md            # Usage and setup instructions
```

