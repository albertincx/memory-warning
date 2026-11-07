#!/usr/bin/env bash
# Helper script to uninstall the memory-warning LaunchAgent.

PLIST_NAME="com.user.memorywarning"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"

if [ -f "$PLIST_PATH" ]; then
    echo "Unloading $PLIST_NAME..."
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    echo "Removed $PLIST_PATH"
    echo "LaunchAgent uninstalled successfully."
else
    echo "LaunchAgent plist not found at $PLIST_PATH."
fi
