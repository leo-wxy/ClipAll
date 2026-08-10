#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
VERSION="$(<"$PROJECT_ROOT/VERSION")"
BUILD_ROOT="$PROJECT_ROOT/.build"
APP_PATH="$BUILD_ROOT/ClipAll.app"
ZIP_PATH="$BUILD_ROOT/ClipAll-${VERSION}-macos-arm64-ad-hoc.zip"
DMG_PATH="$BUILD_ROOT/ClipAll-${VERSION}-macos-arm64-ad-hoc.dmg"
STAGING_DIR="$(/usr/bin/mktemp -d "$BUILD_ROOT/release-stage.XXXXXX")"

cleanup() {
  [[ "$STAGING_DIR" == "$BUILD_ROOT"/release-stage.* ]] || return
  /bin/rm -rf -- "$STAGING_DIR"
}
trap cleanup EXIT

test -d "$APP_PATH"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"

BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
[[ "$BUNDLE_VERSION" == "$VERSION" ]] || {
  print -u2 "App version $BUNDLE_VERSION does not match VERSION $VERSION."
  exit 1
}

/bin/rm -f -- "$ZIP_PATH" "$ZIP_PATH.sha256" "$DMG_PATH" "$DMG_PATH.sha256"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

/usr/bin/ditto "$APP_PATH" "$STAGING_DIR/ClipAll.app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"

verify_dmg() {
  local attempt
  for attempt in 1 2 3; do
    if /usr/bin/hdiutil verify "$DMG_PATH"; then
      return 0
    fi
    if (( attempt < 3 )); then
      print -u2 "DMG verification attempt $attempt failed; retrying in 2 seconds."
      /bin/sleep 2
    fi
  done
  return 1
}

artifacts=("$ZIP_PATH")
if /usr/bin/hdiutil create \
  -volname "ClipAll" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH"; then
  # macOS 15 arm64 runners can return from create before diskimages-helper
  # releases the image. Give it time to settle before the first verification.
  /bin/sleep 6
fi

if [[ -f "$DMG_PATH" ]] && verify_dmg; then
  artifacts+=("$DMG_PATH")
else
  /bin/rm -f -- "$DMG_PATH" "$DMG_PATH.sha256"
  print -u2 "Warning: this runner cannot create a DMG; the ZIP release artifact is still available."
fi

for artifact in "${artifacts[@]}"; do
  (
    cd "$(dirname "$artifact")"
    /usr/bin/shasum -a 256 "$(basename "$artifact")"
  ) > "$artifact.sha256"
done

print "Packaged release artifacts:"
for artifact in "${artifacts[@]}"; do
  print "  $artifact"
done
