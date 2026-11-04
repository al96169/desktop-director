#!/bin/bash
# Build the macOS backend and install it as a signed app bundle.
#
#   ./mac/build.sh              compile + bundle + sign + install (default)
#   ./mac/build.sh --no-install compile only
#
# Why an .app: TCC (accessibility) is granted to the *bundle* com.ddir.mac at
# ~/Applications/Ddir.app. A bare binary run from a shell does not inherit the grant,
# and changing the path/signature forces the user to authorize again (D29/macos-findings).
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
OUT="$ROOT/mac/build"
APP="${DDIR_APP:-$HOME/Applications/Ddir.app}"
KC="${DDIR_KEYCHAIN:-$HOME/.ddir-sign/ddir.keychain-db}"
SIGN_ID="${DDIR_SIGN_ID:-ddir-dev}"

mkdir -p "$OUT"
echo "== swiftc"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  -o "$OUT/ddir-mac" \
  Sources/Util.swift Sources/Store.swift Sources/MacWin.swift Sources/Present.swift \
  Sources/Autostart.swift Sources/Hud.swift Sources/ShowAssets.swift Sources/ShowMedia.swift Sources/Show.swift Sources/Player.swift Sources/Web.swift Sources/Doctor.swift Sources/Tray.swift Sources/Commands.swift Sources/main.swift \
  -framework AppKit -framework ApplicationServices -framework ScreenCaptureKit -framework WebKit -framework AVFoundation -framework CoreText
echo "== built $OUT/ddir-mac ($(du -h "$OUT/ddir-mac" | cut -f1))"

if [ "${1:-}" = "--no-install" ]; then
  exit 0
fi

echo "== bundle $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp "$ROOT/prompts/AGENTS.m0.md" "$APP/Contents/Resources/AGENTS.m0.md"
cp "$OUT/ddir-mac" "$APP/Contents/MacOS/Ddir"

echo "== sign ($SIGN_ID)"
security unlock-keychain -p ddir "$KC" >/dev/null 2>&1 || true
codesign --force --deep --keychain "$KC" -s "$SIGN_ID" "$APP"
codesign --verify "$APP"

# Convenience: a symlink that resolves to the signed binary, so it keeps the TCC grant.
ln -sf "$APP/Contents/MacOS/Ddir" "$OUT/ddir-mac-signed"

mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/ddir" <<EOF
#!/bin/bash
exec "$APP/Contents/MacOS/Ddir" "\$@"
EOF
chmod +x "$HOME/.local/bin/ddir"
echo "== installed: $APP (command: ddir)"
echo "== next: ddir selftest"
