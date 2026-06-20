#!/bin/bash
set -e

# Ensure we run from the project root
cd "$(dirname "$0")"

echo "=== Building PhotomatorSort in Release mode ==="
DEVELOPER_DIR=/Users/oliver/Downloads/Xcode-beta.app/Contents/Developer \
xcodebuild -scheme PhotomatorSort -destination 'platform=macOS' -configuration Release SYMROOT=build OBJROOT=build/intermediates build

echo "=== Creating App Bundle ==="
APP_DIR="PhotomatorSort.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

echo "=== Copying Binaries and Resources ==="
cp build/Release/PhotomatorSort "$APP_DIR/Contents/MacOS/"
cp -R build/Release/PhotomatorSort_PhotomatorSort.bundle "$APP_DIR/Contents/Resources/"
cp PhotomatorSort/Resources/AppIcon.icns "$APP_DIR/Contents/Resources/"

echo "=== Generating Info.plist ==="
cat << 'EOF' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>PhotomatorSort</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIdentifier</key>
    <string>com.oliver.PhotomatorSort</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Photomator Sort</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "=== Codesigning App Bundle ==="
codesign --force --deep --sign - "$APP_DIR"

echo "=== Package Complete: PhotomatorSort.app ==="
