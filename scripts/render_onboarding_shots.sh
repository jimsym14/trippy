#!/bin/zsh
# Re-shoots the real app screens the onboarding cards are built on, so the cards
# always show the current UI. Run after a UI change:
#
#   scripts/render_onboarding_shots.sh [simulator-udid]
#
# It builds the app, launches it in the booted simulator with DEBUG demo flags
# (no network, no account needed), screenshots each screen, trims the status bar
# and writes ios/Trippy/Assets.xcassets/Onboarding*.imageset. Commit the images.
set -euo pipefail
ROOT=${0:A:h:h}
DEVICE=${1:-$(xcrun simctl list devices booted | grep -Eo '[0-9A-F-]{36}' | head -1)}
[[ -n "$DEVICE" ]] || { echo "Boot a simulator first (xcrun simctl boot <udid>)"; exit 1; }
DERIVED=$ROOT/.local/xcode-deriveddata
OUT=$ROOT/ios/Trippy/Assets.xcassets
WORK=$(mktemp -d)
BUNDLE=com.dimitrisymeonidis.trippy

xcodebuild -project $ROOT/ios/Trippy.xcodeproj -scheme Trippy -destination "id=$DEVICE" -derivedDataPath $DERIVED build -quiet
APP=$(find $DERIVED/Build/Products/Debug-iphonesimulator -maxdepth 1 -name 'Trippy.app' | head -1)
xcrun simctl install $DEVICE $APP
xcrun simctl status_bar $DEVICE override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null || true

# The plan card uses a fixed sample plan so it never depends on a live server.
SAMPLE=$ROOT/scripts/fixtures/onboarding-plan.json

shoot() {  # name wait launch-args...
  local name=$1 wait=$2; shift 2
  xcrun simctl terminate $DEVICE $BUNDLE 2>/dev/null || true
  xcrun simctl launch $DEVICE $BUNDLE -TrippySkipOnboarding YES "$@" >/dev/null
  sleep $wait
  xcrun simctl io $DEVICE screenshot --type=png $WORK/$name.png >/dev/null 2>&1
  # The status bar stays (a clean 9:41); 1100 px tall is plenty for a card.
  sips -Z 1100 -s format jpeg -s formatOptions 82 $WORK/$name.png --out $WORK/$name.jpg >/dev/null
  local set=$OUT/Onboarding$name.imageset
  mkdir -p $set && cp $WORK/$name.jpg $set/$name.jpg
  cat > $set/Contents.json <<JSON
{ "images" : [ { "filename" : "$name.jpg", "idiom" : "universal" } ], "info" : { "author" : "xcode", "version" : 1 } }
JSON
  echo "  Onboarding$name ← $*"
}

echo "Shooting onboarding screens on $DEVICE"
shoot Videos 9 -TrippyStudioDemo
shoot Plan 12 -TrippyImportResearch $SAMPLE -TrippyImportStay Trastevere -TrippyStartScreen guide -TrippyGuideDay 2
shoot Been 10 -TrippyStartScreen been
xcrun simctl status_bar $DEVICE clear 2>/dev/null || true
rm -rf $WORK
echo "Done. Rebuild the app to see the new cards."
