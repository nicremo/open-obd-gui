#!/bin/bash
# Builds "Open OBD GUI.app" into dist/ and signs it ad hoc.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIGURATION="${1:-release}"
swift build -c "$CONFIGURATION" --product OpenOBDApp
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP="dist/Open OBD GUI.app"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ditto "$BIN_DIR/OpenOBDApp" "$APP/Contents/MacOS/OpenOBDApp"
ditto "Support/AppInfo.plist" "$APP/Contents/Info.plist"
for bundle in "$BIN_DIR"/*.bundle; do
    ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
done
if [ -f Support/AppIcon.icns ]; then
    ditto Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - "$APP" >/dev/null
echo "Gebaut: $APP"
