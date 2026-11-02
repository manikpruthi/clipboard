#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
APP_NAME="Clipboard Win"
BUILD_DIR="${CLIPBOARD_WIN_BUILD_DIR:-$HOME/Library/Caches/ClipboardWinBuild}"
RELEASE_DIR="release"
APP="$BUILD_DIR/$APP_NAME.app"

./build.sh release

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

diskutil image create from --format UDZO --volumeName "$APP_NAME" \
    "$STAGE" "$RELEASE_DIR/Clipboard-Win-$VERSION.dmg" >/dev/null

touch "$RELEASE_DIR/.metadata_never_index"

echo "Packaged:"
ls -lh "$RELEASE_DIR"
