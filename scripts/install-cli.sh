#!/bin/bash
# Builds openobd in release mode and installs it for the current user.
# Binary and resource bundle go to ~/.local/share/openobd, a small wrapper to ~/.local/bin/openobd.
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release --product openobd
BIN_DIR="$(swift build -c release --show-bin-path)"
TARGET="$HOME/.local/share/openobd"
mkdir -p "$TARGET" "$HOME/.local/bin"

ditto "$BIN_DIR/openobd" "$TARGET/openobd"
for bundle in "$BIN_DIR"/*.bundle; do
    ditto "$bundle" "$TARGET/$(basename "$bundle")"
done

cat > "$HOME/.local/bin/openobd" <<WRAPPER
#!/bin/bash
exec "$TARGET/openobd" "\$@"
WRAPPER
chmod +x "$HOME/.local/bin/openobd"

echo "openobd $("$TARGET/openobd" --version) installed: $HOME/.local/bin/openobd"
