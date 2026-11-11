#!/bin/zsh
# Build Earshot.app, sign it, install to /Applications and (re)launch it.
set -euo pipefail
cd "${0:A:h}"

APP=build/Earshot.app
IDENTITY="${SIGN_IDENTITY:-$(cat .sign-identity 2>/dev/null || echo -)}"  # "-" = ad-hoc

rm -rf build && mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources" && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/Earshot" Sources/main.swift
codesign --force --options runtime --sign "$IDENTITY" "$APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Earshot || true
  rm -rf /Applications/Earshot.app
  cp -R "$APP" /Applications/
  open /Applications/Earshot.app
  echo "Installed and launched /Applications/Earshot.app"
fi
