#!/bin/bash
set -euo pipefail

SCHEME="MoltNotch"
PROJECT="MoltNotch.xcodeproj"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/MoltNotch.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_NAME="MoltNotch.dmg"

echo "==> Generating Xcode project..."
xcodegen generate

echo "==> Archiving $SCHEME..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO

echo "==> Exporting app..."
mkdir -p "$EXPORT_PATH"
cp -R "$ARCHIVE_PATH/Products/Applications/MoltNotch.app" "$EXPORT_PATH/"

echo "==> Building CLI tool..."
xcodebuild build \
    -project "$PROJECT" \
    -scheme MoltNotchCLI \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/cli-derived"

CLI_BINARY=$(find "$BUILD_DIR/cli-derived" -name "MoltNotchCLI" -type f | head -1)
if [ -n "$CLI_BINARY" ]; then
    cp "$CLI_BINARY" "$EXPORT_PATH/moltnotch"
    echo "==> CLI binary copied to $EXPORT_PATH/moltnotch"
fi

echo "==> Creating DMG..."
hdiutil create -volname "MoltNotch" \
    -srcfolder "$EXPORT_PATH" \
    -ov -format UDZO \
    "$BUILD_DIR/$DMG_NAME"

echo "==> Done! Output: $BUILD_DIR/$DMG_NAME"
echo ""
echo "To notarize (requires Apple Developer account):"
echo "  xcrun notarytool submit $BUILD_DIR/$DMG_NAME --apple-id YOUR_ID --team-id YOUR_TEAM --password YOUR_PASSWORD"
echo "  xcrun stapler staple $BUILD_DIR/$DMG_NAME"
