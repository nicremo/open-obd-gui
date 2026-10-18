#!/bin/bash
# Builds the release artifacts into dist/release: the app as zip, the command line tool as tar.gz, SHA-256 checksums.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/AppInfo.plist)"
OUT="dist/release"
APP_ZIP="Open-OBD-GUI-$VERSION-macOS-arm64.zip"
CLI_NAME="openobd-$VERSION-macos-arm64"

scripts/build-app.sh release
swift build -c release --product openobd
BIN_DIR="$(swift build -c release --show-bin-path)"

mkdir -p "$OUT/$CLI_NAME"
ditto -c -k --sequesterRsrc --keepParent "dist/Open OBD GUI.app" "$OUT/$APP_ZIP"
ditto "$BIN_DIR/openobd" "$OUT/$CLI_NAME/openobd"
for bundle in "$BIN_DIR"/*.bundle; do
    ditto "$bundle" "$OUT/$CLI_NAME/$(basename "$bundle")"
done
tar -C "$OUT" -czf "$OUT/$CLI_NAME.tar.gz" "$CLI_NAME"
(cd "$OUT" && shasum -a 256 "$APP_ZIP" "$CLI_NAME.tar.gz" > SHA256SUMS.txt)

echo "Release $VERSION in $OUT:"
cat "$OUT/SHA256SUMS.txt"
