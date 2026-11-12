#!/usr/bin/env bash
# Builds a standalone native macOS .app bundle for Memory Warning (Menu Bar / Tray app)
# Uses Swift / AppKit so it runs on ANY Mac without requiring Python or external dependencies.

set -e

APP_NAME="Memory Warning"
BUNDLE_DIR="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Building ${BUNDLE_DIR} (Native Swift Universal Binary)..."

# Clean up any existing bundle
rm -rf "${BUNDLE_DIR}"

# Create bundle directory hierarchy
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Compile Native Swift Binary (Universal arm64 + x86_64 if supported, fallback to host arch)
if swiftc -O -target arm64-apple-macos11.0 "${PROJECT_DIR}/macos/main.swift" -o "${MACOS_DIR}/MemoryWarning_arm64" 2>/dev/null && \
   swiftc -O -target x86_64-apple-macos11.0 "${PROJECT_DIR}/macos/main.swift" -o "${MACOS_DIR}/MemoryWarning_x86_64" 2>/dev/null; then
    lipo -create -output "${MACOS_DIR}/Memory Warning" "${MACOS_DIR}/MemoryWarning_arm64" "${MACOS_DIR}/MemoryWarning_x86_64"
    rm -f "${MACOS_DIR}/MemoryWarning_arm64" "${MACOS_DIR}/MemoryWarning_x86_64"
    echo "✅ Compiled Universal Binary (arm64 + x86_64)"
else
    swiftc -O "${PROJECT_DIR}/macos/main.swift" -o "${MACOS_DIR}/Memory Warning"
    echo "✅ Compiled Native Host Binary"
fi

chmod +x "${MACOS_DIR}/Memory Warning"

# Copy application icon if present
if [ -f "${PROJECT_DIR}/macos/AppIcon.icns" ]; then
    cp "${PROJECT_DIR}/macos/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# Create Info.plist
# LSUIElement=true hides the app from the Dock so it runs purely in the Menu Bar (tray).
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
    <string>0.3.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleExecutable</key>
    <string>Memory Warning</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Ad-hoc code sign the bundle so macOS Gatekeeper allows local execution cleanly
codesign --force --deep --sign - "${BUNDLE_DIR}" 2>/dev/null || true
touch "${BUNDLE_DIR}"

echo "✅ Successfully built: ${PROJECT_DIR}/${BUNDLE_DIR}"
echo "You can now double-click '${APP_NAME}.app' in Finder or drag it to /Applications!"
