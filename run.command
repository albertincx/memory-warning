#!/bin/bash
# Double-clickable macOS command script to launch Memory Warning
cd "$(dirname "$0")"

# Check if rumps is installed to decide whether to launch GUI or CLI daemon
if python3 -c "import rumps" 2>/dev/null; then
    echo "Starting Memory Warning Menu Bar (Tray) App..."
    python3 menubar.py
else
    echo "rumps not found. Starting Memory Warning CLI Daemon..."
    echo "Tip: Run 'pip install -r requirements.txt' to enable the Menu Bar Tray UI."
    python3 memory_monitor.py --threshold 1GB --interval 15
fi

