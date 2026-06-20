#!/bin/bash
set -e

# Ensure we run from the project root
cd "$(dirname "$0")"

APP_NAME="PhotomatorSort.app"
DMG_NAME="PhotomatorSort.dmg"
WORKSPACE="dmg_workspace"

if [ ! -d "$APP_NAME" ]; then
    echo "Error: $APP_NAME not found! Run ./package_app.sh first."
    exit 1
fi

echo "=== Creating DMG Workspace ==="
rm -rf "$WORKSPACE"
mkdir -p "$WORKSPACE"

echo "=== Copying App Bundle ==="
cp -R "$APP_NAME" "$WORKSPACE/"

echo "=== Creating Applications Symlink ==="
ln -s /Applications "$WORKSPACE/Applications"

echo "=== Building Compressed DMG ==="
rm -f "$DMG_NAME"
hdiutil create -volname "Photomator Sort" -srcfolder "$WORKSPACE" -ov -format UDZO "$DMG_NAME"

echo "=== Cleaning Up ==="
rm -rf "$WORKSPACE"

echo "=== DMG Build Complete: $DMG_NAME ==="
