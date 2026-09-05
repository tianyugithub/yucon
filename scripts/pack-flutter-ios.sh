#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/app"
cd "$APP"

echo "Building Flutter iOS release app..."
flutter build ios --release

APP_BUNDLE="$APP/build/ios/iphoneos/Runner.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "iOS app not found: $APP_BUNDLE" >&2
  exit 1
fi

DEST_DIR="$ROOT/dist"
DEST_APP="$DEST_DIR/yucon-vault-release.app"
mkdir -p "$DEST_DIR"
rm -rf "$DEST_APP"
cp -R "$APP_BUNDLE" "$DEST_APP"
echo "App: $DEST_APP ($(du -sh "$DEST_APP" | awk '{print $1}'))"

IOS_DEVICE="$(flutter devices --machine | python3 -c '
import json, sys
devices = json.load(sys.stdin)
for device in devices:
    if device.get("targetPlatform") == "ios" and not device.get("emulator", False):
        print(device.get("id", ""))
        break
')"

if [[ -z "${IOS_DEVICE}" ]]; then
  echo "No physical iPhone connected. App is ready at $DEST_APP"
  exit 0
fi

echo "Installing onto iPhone ($IOS_DEVICE)..."
flutter install --release -d "$IOS_DEVICE"
echo "Installed cc.yucon.vault"
