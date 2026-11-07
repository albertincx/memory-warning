#!/usr/bin/env bash
# Helper script to install the macOS Menu Bar app as a user Login LaunchAgent.

set -e

PLIST_NAME="com.user.memorywarning.menubar"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/menubar.py"
PYTHON_BIN="$(which python3)"
LOG_DIR="$HOME/Library/Logs/memory-warning"

mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$LOG_DIR"

echo "Creating Menu Bar LaunchAgent: $PLIST_PATH"
echo "Target script:                 $SCRIPT_PATH"
echo "Python binary:                 $PYTHON_BIN"

# Unload previous instance if active
if launchctl list | grep -q "$PLIST_NAME"; then
    echo "Stopping existing menubar instance..."
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
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/menubar_stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/menubar_stderr.log</string>
</dict>
</plist>
EOF

chmod 644 "$PLIST_PATH"
launchctl load "$PLIST_PATH"

echo "Successfully registered and started $PLIST_NAME!"
echo "The 💾 icon should now be visible in your top macOS menu bar."
echo "Logs are located at: $LOG_DIR"

