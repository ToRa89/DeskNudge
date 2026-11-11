#!/bin/zsh
# Baut DeskNudge.app in ./build. Nutzung: ./build.sh [--install]  (--install kopiert nach ~/Applications)
set -euo pipefail
cd "$(dirname "$0")"
swift test
swift build -c release
APP=build/DeskNudge.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/DeskNudge" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "Gebaut: $APP"
if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/DeskNudge.app
  cp -R "$APP" ~/Applications/
  echo "Installiert: ~/Applications/DeskNudge.app"
fi
