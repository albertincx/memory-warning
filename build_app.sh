#!/usr/bin/env bash
# Builds a standalone macOS .app bundle for Memory Warning (Menu Bar / Tray app)

set -e

APP_NAME="Memory Warning"
BUNDLE_DIR="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Building ${BUNDLE_DIR}..."

# Clean up any existing bundle
rm -rf "${BUNDLE_DIR}"

# Create bundle directory hierarchy
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy python files to Resources
cp "${PROJECT_DIR}/menubar.py" "${RESOURCES_DIR}/"
cp "${PROJECT_DIR}/memory_monitor.py" "${RESOURCES_DIR}/"

# Create Info.plist
# Note: LSUIElement=true hides the app from the Dock, so it acts purely as a menu bar / tray app.
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.user.memorywarning</string>
    <key>CFBundleVersion</key>
    <string>0.2.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleExecutable</key>
    <string>Memory Warning</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Create executable launcher inside MacOS/
cat <<'EOF' > "${MACOS_DIR}/Memory Warning"
#!/bin/bash
RESOURCES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../Resources" && pwd)"
LOG_DIR="$HOME/Library/Logs/memory-warning"
mkdir -p "$LOG_DIR"

# Locate python3 binary with dependencies
PYTHON_BIN=""
CANDIDATES=(
    "$(which python3 2>/dev/null)"
    "/opt/homebrew/bin/python3"
    "/usr/local/bin/python3"
    "/usr/bin/python3"
)

# Look for Python that can import rumps
for p in "${CANDIDATES[@]}"; do
    if [ -x "$p" ] && "$p" -c "import rumps" 2>/dev/null; then
        PYTHON_BIN="$p"
        break
    fi
done

if [ -z "$PYTHON_BIN" ]; then
    PYTHON_BIN="$(which python3 || echo '/usr/bin/python3')"
fi

cd "$RESOURCES_DIR"
exec "$PYTHON_BIN" "$RESOURCES_DIR/menubar.py" >> "$LOG_DIR/app_stdout.log" 2>> "$LOG_DIR/app_stderr.log"
EOF

chmod +x "${MACOS_DIR}/Memory Warning"

echo "✅ Successfully built: ${PROJECT_DIR}/${BUNDLE_DIR}"
echo "You can now double-click '${APP_NAME}.app' in Finder or drag it to /Applications!"

