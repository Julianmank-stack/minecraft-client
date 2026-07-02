#!/bin/bash
# Builds MetalCraft.app from the Swift package and (optionally) installs it
# into /Applications. Run this on your Mac (needs Xcode or the Command Line
# Tools with a full Swift toolchain):
#
#   ./scripts/package-app.sh              # build → dist/MetalCraft.app
#   ./scripts/package-app.sh --install    # build + copy into /Applications
#
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname)" != "Darwin" ]]; then
    echo "error: MetalCraft.app can only be built on macOS." >&2
    exit 1
fi

echo "▸ Building launcher (release)…"
swift build -c release --package-path Launcher

APP="dist/MetalCraft.app"
BINARY="Launcher/.build/release/MetalCraftLauncher"

echo "▸ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/MetalCraft"
cp scripts/Info.plist "$APP/Contents/Info.plist"

# App icon: put an icon.icns at scripts/icon.icns to have it bundled.
if [[ -f scripts/icon.icns ]]; then
    cp scripts/icon.icns "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

echo "▸ Code signing (ad-hoc)…"
codesign --force --deep --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
    # /Applications needs admin rights; fall back to ~/Applications otherwise.
    DEST="/Applications"
    if [[ ! -w "$DEST" ]]; then
        DEST="$HOME/Applications"
        mkdir -p "$DEST"
        echo "▸ /Applications is not writable — installing to $DEST instead…"
    else
        echo "▸ Installing to $DEST…"
    fi
    rm -rf "$DEST/MetalCraft.app"
    cp -R "$APP" "$DEST/"
    echo "✓ Installed. Launch it from Spotlight (⌘Space → MetalCraft) or $DEST."
    open -R "$DEST/MetalCraft.app"
else
    echo "✓ Built $APP"
    echo "  Drag it into /Applications, or re-run with --install."
    open -R "$APP"
fi
