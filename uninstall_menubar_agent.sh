#!/usr/bin/env bash
# Helper script to uninstall the macOS Menu Bar LaunchAgent.

PLIST_NAME="com.user.memorywarning.menubar"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"

if [ -f "$PLIST_PATH" ]; then
    echo "Unloading $PLIST_NAME..."
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    echo "Removed $PLIST_PATH"
    echo "Menu Bar LaunchAgent uninstalled successfully."
else
    echo "Menu Bar LaunchAgent plist not found at $PLIST_PATH."
fi

