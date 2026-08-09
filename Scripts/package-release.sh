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
/usr/bin/hdiutil create \
  -volname "ClipAll" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH"
/usr/bin/hdiutil verify "$DMG_PATH"

for artifact in "$ZIP_PATH" "$DMG_PATH"; do
  (
    cd "$(dirname "$artifact")"
    /usr/bin/shasum -a 256 "$(basename "$artifact")"
  ) > "$artifact.sha256"
done

print "Packaged release artifacts:"
print "  $ZIP_PATH"
print "  $DMG_PATH"
