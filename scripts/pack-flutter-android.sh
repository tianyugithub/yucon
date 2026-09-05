#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/app"
cd "$APP"

export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:${PATH:-}"

if [[ ! -x "$JAVA_HOME/bin/java" ]]; then
  echo "Java not found. Set JAVA_HOME to a JDK 17+ install." >&2
  exit 1
fi

printf 'sdk.dir=%s\n' "$ANDROID_HOME" > android/local.properties

echo "Using JAVA_HOME=$JAVA_HOME"
"$JAVA_HOME/bin/java" -version

echo "Building Flutter debug APK..."
flutter build apk --debug

APK="$APP/build/app/outputs/flutter-apk/app-debug.apk"
if [[ ! -f "$APK" ]]; then
  echo "APK not found: $APK" >&2
  exit 1
fi

DEST="$ROOT/dist/yucon-vault-debug.apk"
mkdir -p "$ROOT/dist"
cp "$APK" "$DEST"
echo "APK: $DEST ($(du -h "$DEST" | awk '{print $1}'))"

if ! adb get-state >/dev/null 2>&1; then
  echo "No Android device connected. APK is ready at $DEST" >&2
  exit 0
fi

echo "Installing onto connected device..."
adb install -r "$DEST"
adb shell dumpsys package cc.yucon.vault | awk '/versionName|versionCode/{print; if ($0 ~ /versionName/) exit}'
echo "Installed cc.yucon.vault"
