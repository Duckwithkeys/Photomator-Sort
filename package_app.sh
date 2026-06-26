#!/bin/bash
set -e

# Ensure we run from the project root
cd "$(dirname "$0")"

echo "=== Building DuckSort in Release mode ==="
# Use the beta Xcode if it exists and DEVELOPER_DIR is not already set
if [ -z "$DEVELOPER_DIR" ] && [ -d "/Users/oliver/Downloads/Xcode-beta.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Users/oliver/Downloads/Xcode-beta.app/Contents/Developer"
fi

xcodebuild -scheme DuckSort -destination 'platform=macOS' -configuration Release SYMROOT=build OBJROOT=build/intermediates build

echo "=== Creating App Bundle ==="
APP_DIR="DuckSort.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

echo "=== Copying Binaries and Resources ==="
cp build/Release/DuckSort "$APP_DIR/Contents/MacOS/"
cp -R build/Release/DuckSort_DuckSort.bundle "$APP_DIR/Contents/Resources/"
cp DuckSort/Resources/AppIcon.icns "$APP_DIR/Contents/Resources/"

echo "=== Generating Info.plist ==="
cat << 'EOF' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>DuckSort</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIdentifier</key>
    <string>com.oliver.DuckSort</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>DuckSort</string>
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
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.ducksort.tagpack</string>
            <key>UTTypeDescription</key>
            <string>DuckSort Tag Pack</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.json</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>tagpack</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "=== Codesigning App Bundle ==="
xattr -cr build/Release || true
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"

echo "=== Package Complete: DuckSort.app ==="
