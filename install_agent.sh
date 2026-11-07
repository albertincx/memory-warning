#!/usr/bin/env bash
# Helper script to install memory-warning as a macOS background LaunchAgent.

set -e

PLIST_NAME="com.user.memorywarning"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/memory_monitor.py"
PYTHON_BIN="$(which python3)"
LOG_DIR="$HOME/Library/Logs/memory-warning"
THRESHOLD="${1:-1GB}"
INTERVAL="${2:-15}"
LANG_OPT="${3:-auto}"

mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$LOG_DIR"

echo "Creating LaunchAgent: $PLIST_PATH"
echo "Target script:        $SCRIPT_PATH"
echo "Python binary:        $PYTHON_BIN"
echo "Memory Threshold:     $THRESHOLD"
echo "Check Interval:       ${INTERVAL}s"
echo "Language:             $LANG_OPT"

# Unload previous instance if running
if launchctl list | grep -q "$PLIST_NAME"; then
    echo "Stopping existing instance..."
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
fi

cat <<EOF > "$PLIST_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${PYTHON_BIN}</string>
        <string>${SCRIPT_PATH}</string>
        <string>--threshold</string>
        <string>${THRESHOLD}</string>
        <string>--interval</string>
        <string>${INTERVAL}</string>
        <string>--lang</string>
        <string>${LANG_OPT}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/stderr.log</string>
</dict>
</plist>
EOF

chmod 644 "$PLIST_PATH"
launchctl load "$PLIST_PATH"

echo "Successfully loaded and started $PLIST_NAME!"
echo "Logs are located at: $LOG_DIR"
