#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export JAVA_HOME="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"

if [[ ! -x "$JAVA_HOME/bin/java" ]]; then
  echo "JDK 21 not found at $JAVA_HOME" >&2
  exit 1
fi
if [[ ! -d "$ANDROID_HOME/platforms/android-35" ]]; then
  echo "Android SDK 35 not found at $ANDROID_HOME" >&2
  exit 1
fi

echo "Using JAVA_HOME=$JAVA_HOME"
"$JAVA_HOME/bin/java" -version

echo "Building H5 resources for Android WebView..."
YUCON_NATIVE=1 npx uni build

if [[ ! -d android ]]; then
  echo "Creating Capacitor Android project..."
  npx cap add android
fi

npx cap sync android

printf 'sdk.dir=%s\n' "$ANDROID_HOME" > android/local.properties

VARIABLES_FILE="android/variables.gradle"
if [[ -f "$VARIABLES_FILE" ]]; then
  python3 - <<'PY'
from pathlib import Path
path = Path("android/variables.gradle")
text = path.read_text()
text = text.replace("minSdkVersion = 22", "minSdkVersion = 26")
text = text.replace("minSdkVersion = 23", "minSdkVersion = 26")
path.write_text(text)
PY
fi

ICON_SRC="$ROOT/src/static/brand/yucon-app-icon.png"
if [[ -f "$ICON_SRC" ]]; then
  echo "Writing launcher icons..."
  python3 - <<'PY'
from pathlib import Path
import subprocess
root = Path("android/app/src/main/res")
src = Path("src/static/brand/yucon-app-icon.png")
sizes = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
for folder, size in sizes.items():
    dest_dir = root / folder
    dest_dir.mkdir(parents=True, exist_ok=True)
    for name in ("ic_launcher.png", "ic_launcher_round.png", "ic_launcher_foreground.png"):
        dest = dest_dir / name
        subprocess.run(
            ["sips", "-z", str(size), str(size), str(src), "--out", str(dest)],
            check=True,
            stdout=subprocess.DEVNULL,
        )
PY
fi

echo "Assembling debug APK..."
(
  cd android
  ./gradlew assembleDebug --no-daemon
)

APK="$ROOT/android/app/build/outputs/apk/debug/app-debug.apk"
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
