#!/bin/sh
# Builds NoSpeaker.app.
#
#   ./build-app.sh            build build/NoSpeaker.app
#   ./build-app.sh install    also copy it to ~/Applications
#
# Signs with your Apple Development identity when there is one, so macOS remembers the permissions you give it
# (listening to Music, controlling Music) across rebuilds; otherwise signs for this Mac only.
set -e
cd "$(dirname "$0")"

echo "building…"
swift build -c release --product NoSpeaker
app=build/NoSpeaker.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/NoSpeaker "$app/Contents/MacOS/NoSpeaker"
cp Support/Info.plist "$app/Contents/Info.plist"

# The icon: the artwork chosen from ../design/icon/ (made with Codex image generation), fitted to the macOS grid.
icon="${NOSPEAKER_ICON:-../design/icon/icon-a.png}"
echo "making the icon from $icon…"
rm -rf build/NoSpeaker.iconset
swift Support/make-icon.swift "$icon" build/NoSpeaker.iconset ../docs/images/icon.png >/dev/null
iconutil -c icns build/NoSpeaker.iconset -o "$app/Contents/Resources/NoSpeaker.icns"

identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -n 1)
codesign --force --sign "${identity:--}" "$app"
codesign --verify --strict "$app"
echo "built $app (signed: ${identity:-this Mac only})"

if [ "$1" = "install" ]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/NoSpeaker.app"
    cp -R "$app" "$HOME/Applications/NoSpeaker.app"
    echo "installed ~/Applications/NoSpeaker.app"
fi
