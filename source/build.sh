#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP='紫色小伙伴.app'
ASSETS="${PET_ASSETS_DIR:-assets-local}"
[[ "$(uname -s)" == Darwin ]] || { echo '需要 macOS 与 Xcode Command Line Tools'; exit 1; }
[[ -f "$ASSETS/spritesheet-clean.png" ]] || { echo '缺少本机皮肤；先执行 bash prepare-assets.sh'; exit 1; }
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp "$ASSETS/spritesheet-clean.png" chat-config.json tongji-notices.json "$APP/Contents/Resources/"
for skin in skin-blue-cat skin-charcoal-cat skin-heart-buddy; do
  rm -f "$APP/Contents/Resources/$skin.png"
  if [[ -f "$ASSETS/$skin.png" ]]; then cp "$ASSETS/$skin.png" "$APP/Contents/Resources/"; fi
done
swiftc -O -target arm64-apple-macos12 -framework AppKit -framework Security -framework WebKit -framework ScriptingBridge main.swift chat.swift news.swift rank.swift aa-rank.swift arena-rank.swift music.swift gallery.swift restart.swift settings.swift skins.swift -o "$APP/Contents/MacOS/PurplePet"
codesign --force --sign - "$APP"
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/pet-source-selftest.XXXXXX")"
trap 'rm -rf "$TEST_HOME"' EXIT
HOME="$TEST_HOME" CFFIXED_USER_HOME="$TEST_HOME" CFPREFERENCES_AVOID_DAEMON=1 "$APP/Contents/MacOS/PurplePet" --self-test
