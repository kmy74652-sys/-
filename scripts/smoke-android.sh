#!/usr/bin/env bash
set -euo pipefail

apk="$GITHUB_WORKSPACE/apps/mobile/android/app/build/outputs/apk/release/app-release.apk"
test -s "$apk"
app_id="$(node -e 'console.log(require(process.env.GITHUB_WORKSPACE + "/apps/mobile/app.json").expo.android.package)')"
test -n "$app_id"

echo "Installing $apk for $app_id"
adb install -r "$apk"
adb logcat -c
adb shell monkey -p "$app_id" -c android.intent.category.LAUNCHER 1
sleep 15

if ! adb shell pidof "$app_id" >/dev/null; then
  echo "Android app process did not remain alive: $app_id"
  adb logcat -d -t 2000
  exit 1
fi

if adb logcat -d -t 2000 | grep -E "FATAL EXCEPTION|Process: $app_id"; then
  echo "Android launch smoke test detected a crash for $app_id."
  exit 1
fi

echo "Android launch smoke test passed: $app_id remained alive."
