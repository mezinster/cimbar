#!/bin/bash
# Boots an iPhone Pro Max and a 13-inch iPad simulator, installs a debug build of
# CimBar Scanner on both and prepares them for App Store screenshots.
# Screenshots taken with Simulator's File > Save Screen (Cmd-S) land in store-screens/shots.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/store-screens/shots"; mkdir -p "$OUT"

read -r IPHONE IPAD < <(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
d = json.load(sys.stdin)["devices"]
def ver(rt):
    m = re.search(r"iOS-(\d+)-(\d+)", rt); return (int(m[1]), int(m[2])) if m else (0, 0)
best = {}
for rt in sorted((r for r in d if "iOS" in r), key=ver):
    for dev in d[rt]:
        n = dev["name"]
        if re.search(r"iPhone \d+ Pro Max$", n): best["iphone"] = (dev["udid"], n, rt)
        if re.search(r"iPad Pro.*13", n): best["ipad"] = (dev["udid"], n, rt)
for k in ("iphone", "ipad"):
    if k not in best: sys.exit("No %s simulator found: install one in Xcode > Settings > Components" % k)
    print(best[k][1], "|", best[k][2], file=sys.stderr)
print(best["iphone"][0], best["ipad"][0])
')

defaults write com.apple.iphonesimulator ScreenShotSaveLocation -string "$OUT"
for U in "$IPHONE" "$IPAD"; do xcrun simctl boot "$U" 2>/dev/null || true; done
open -a Simulator
for U in "$IPHONE" "$IPAD"; do
  xcrun simctl bootstatus "$U" -b >/dev/null
  xcrun simctl ui "$U" appearance light
  xcrun simctl status_bar "$U" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
done

cd "$ROOT/app"
flutter pub get
flutter build ios --simulator --debug
APP="$ROOT/app/build/ios/iphonesimulator/Runner.app"
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
for U in "$IPHONE" "$IPAD"; do
  xcrun simctl install "$U" "$APP"
  xcrun simctl addmedia "$U" "$ROOT/test-data/goldens/hello.gif" || true
  xcrun simctl launch "$U" "$BUNDLE"
done
echo
echo "READY: CimBar is running on both simulators. Screenshots go to $OUT"
