#!/bin/bash
# App Store screenshots for CimBar Scanner, captured on iOS simulators.
#
#   bash store-screens/capture.sh                 # iPhone + iPad, en ru uk pl tr
#   LOCALES=en,ru DEVICES=iphone bash store-screens/capture.sh
#
# Boots the newest "iPhone N Pro Max" and "iPad Pro 13-inch" simulators, sets a
# clean 9:41 status bar, then runs app/integration_test/store_screenshots_test.dart
# on each. The test walks Send → Present → Camera → Received → Files in every
# language and asks for a screenshot at each step; this script takes it with
# `xcrun simctl io <device> screenshot` (full resolution, real status bar).
#
# Output: store-screens/captures/<iphone|ipad>/<locale>/<screen>.png
set -euo pipefail
if [ "$(id -u)" = 0 ]; then echo "Run this without sudo: simulators and Flutter must run as your own user." >&2; exit 1; fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/store-screens/captures"
LOCALES="${LOCALES:-en,ru,uk,pl,tr}"
DEVICES="${DEVICES:-iphone,ipad}"

read -r IPHONE IPAD < <(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
d = json.load(sys.stdin)["devices"]
def ver(rt):
    m = re.search(r"iOS-(\d+)-(\d+)", rt); return (int(m[1]), int(m[2])) if m else (0, 0)
best = {}
for rt in sorted((r for r in d if "iOS" in r), key=ver):
    for dev in d[rt]:
        n = dev["name"]
        if re.search(r"iPhone \d+ Pro Max$", n): best["iphone"] = (dev["udid"], n)
        if re.search(r"iPad Pro.*13", n): best["ipad"] = (dev["udid"], n)
for k in ("iphone", "ipad"):
    if k not in best: sys.exit("No %s simulator found: install one in Xcode > Settings > Components" % k)
    print(k, "=", best[k][1], file=sys.stderr)
print(best["iphone"][0], best["ipad"][0])
')

REQ="$(mktemp -d /tmp/cimbar-shots.XXXXXX)"
WATCHER=""
cleanup() { [ -n "$WATCHER" ] && kill "$WATCHER" 2>/dev/null || true; rm -rf "$REQ"; }
trap cleanup EXIT

# Takes a screenshot whenever the test drops a req-<locale>__<screen> file in $REQ.
watch_requests() {
  local udid="$1" dest="$2"
  while true; do
    for req in "$REQ"/req-*; do
      [ -e "$req" ] || continue
      local name="${req##*/req-}"
      local locale="${name%%__*}" screen="${name#*__}"
      mkdir -p "$dest/$locale"
      xcrun simctl io "$udid" screenshot --type=png "$dest/$locale/$screen.png" >/dev/null 2>&1 \
        && echo "  saved $locale/$screen.png" || echo "  FAILED to save $locale/$screen.png" >&2
      rm -f "$req"
      touch "$REQ/done-$name"
    done
    sleep 0.2
  done
}

open "$(xcode-select -p)/Applications/Simulator.app"
cd "$ROOT/app"
flutter pub get >/dev/null

IFS=',' read -r -a WANT <<< "$DEVICES"
for dev in "${WANT[@]}"; do
  case "$dev" in
    iphone) UDID="$IPHONE" ;;
    ipad) UDID="$IPAD" ;;
    *) echo "Unknown device '$dev' (use iphone and/or ipad)" >&2; exit 1 ;;
  esac
  echo "== $dev"
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null
  xcrun simctl ui "$UDID" appearance light
  xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

  watch_requests "$UDID" "$OUT/$dev" &
  WATCHER=$!
  flutter test integration_test/store_screenshots_test.dart -d "$UDID" \
    --dart-define=SHOT_DIR="$REQ" --dart-define=LOCALES="$LOCALES"
  kill "$WATCHER" 2>/dev/null || true
  WATCHER=""
done

echo
echo "DONE: screenshots are in $OUT"
