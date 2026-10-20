#!/bin/sh
# Builds a Release version of Paltsuun and installs it to /Applications.

set -eu

cd "$(dirname "$0")"

BUILD_DIR=/tmp/Paltsuun-build
APP="$BUILD_DIR/Build/Products/Release/Paltsuun.app"
DEST=/Applications/Paltsuun.app

xcodebuild -project Paltsuun.xcodeproj \
  -scheme Paltsuun \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  build

# Quit the running app so it can be replaced.
was_running=false
if pgrep -xq Paltsuun; then
  was_running=true
  osascript -e 'quit app "Paltsuun"'
  while pgrep -xq Paltsuun; do sleep 0.2; done
fi

rm -rf "$DEST"
ditto "$APP" "$DEST"
echo "Installed $DEST"

if $was_running; then
  open "$DEST"
fi
