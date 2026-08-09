#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
MODULE_CACHE="$PROJECT_ROOT/.swift-module-cache"
ARCH="$(uname -m)"
BUILD_DIR="$PROJECT_ROOT/.build/${ARCH}-apple-macosx/debug"
APP_PATH="$PROJECT_ROOT/.build/ClipAll.app"
CONTENTS="$APP_PATH/Contents"
INFO_PLIST="$PROJECT_ROOT/Support/ClipAll-Info.plist"
ENTITLEMENTS="$PROJECT_ROOT/Support/ClipAll.entitlements"
APP_ICON="$PROJECT_ROOT/Support/AppIcon.icns"
MENU_BAR_ICON="$PROJECT_ROOT/Support/MenuBarIcon.svg"
TIMESTAMP_PLUGIN="$PROJECT_ROOT/Plugins/Examples/TimestampTools.clipallplugin"
SIGNING_IDENTITY="${CLIPALL_SIGNING_IDENTITY:-ClipAll Local Development}"
KEYCHAIN_PATH="${CLIPALL_KEYCHAIN_PATH:-$HOME/Library/Keychains/login.keychain-db}"
USE_ADHOC="${CLIPALL_ADHOC:-0}"

[[ "$APP_PATH" == "$PROJECT_ROOT/.build/ClipAll.app" ]] || {
  print -u2 "拒绝覆盖非预期路径：$APP_PATH"
  exit 1
}

mkdir -p "$MODULE_CACHE"

for product in ClipAll ClipAllPluginRunner; do
  env \
    CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
    SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
    swift build \
      --package-path "$PROJECT_ROOT" \
      --scratch-path "$PROJECT_ROOT/.build" \
      --disable-sandbox \
      --build-system native \
      --configuration debug \
      --product "$product"
done

test -x "$BUILD_DIR/ClipAll"
test -x "$BUILD_DIR/ClipAllPluginRunner"
test -f "$APP_ICON"
test -f "$MENU_BAR_ICON"
test -f "$TIMESTAMP_PLUGIN/plugin.json"
test -f "$TIMESTAMP_PLUGIN/main.js"
/usr/bin/plutil -lint "$INFO_PLIST" "$ENTITLEMENTS"

rm -rf -- "$APP_PATH"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$INFO_PLIST" "$CONTENTS/Info.plist"
cp "$BUILD_DIR/ClipAll" "$CONTENTS/MacOS/ClipAll"
cp "$BUILD_DIR/ClipAllPluginRunner" "$CONTENTS/MacOS/ClipAllPluginRunner"
cp "$APP_ICON" "$CONTENTS/Resources/AppIcon.icns"
cp "$MENU_BAR_ICON" "$CONTENTS/Resources/MenuBarIcon.svg"
/usr/bin/ditto \
  "$TIMESTAMP_PLUGIN" \
  "$CONTENTS/Resources/TimestampTools.clipallplugin"

/usr/bin/plutil -lint "$CONTENTS/Info.plist"
/usr/bin/cmp -s "$INFO_PLIST" "$CONTENTS/Info.plist"
test -f "$CONTENTS/Resources/TimestampTools.clipallplugin/plugin.json"
test -f "$CONTENTS/Resources/TimestampTools.clipallplugin/main.js"
test -f "$CONTENTS/Resources/TimestampTools.clipallplugin/Tests/cases.json"
test -f "$CONTENTS/Resources/AppIcon.icns"
test -f "$CONTENTS/Resources/MenuBarIcon.svg"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$CONTENTS/Info.plist")" = "ClipAll"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CONTENTS/Info.plist")" = "com.wxy.ClipAll"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$CONTENTS/Info.plist")" = "AppIcon"

if [[ "$USE_ADHOC" == "1" ]]; then
  SIGNING_VALUE="-"
  SIGNING_KEYCHAIN_ARGS=()
  print "Warning: using ad-hoc signing; Accessibility permission may reset after rebuilds."
else
  SIGNING_VALUE="$(
    security find-identity -v -p codesigning "$KEYCHAIN_PATH" 2>/dev/null \
      | awk -v name="$SIGNING_IDENTITY" 'index($0, "\"" name "\"") { print $2; exit }'
  )"
  if [[ -z "$SIGNING_VALUE" ]]; then
    print -u2 "Missing local signing identity: $SIGNING_IDENTITY"
    print -u2 "Run ./Scripts/setup-local-signing.sh once, then rebuild."
    print -u2 "For disposable CI artifacts only, set CLIPALL_ADHOC=1."
    exit 1
  fi
  SIGNING_KEYCHAIN_ARGS=(--keychain "$KEYCHAIN_PATH")
fi

/usr/bin/codesign \
  --force \
  "${SIGNING_KEYCHAIN_ARGS[@]}" \
  --sign "$SIGNING_VALUE" \
  "$CONTENTS/MacOS/ClipAllPluginRunner"
/usr/bin/codesign \
  --force \
  "${SIGNING_KEYCHAIN_ARGS[@]}" \
  --sign "$SIGNING_VALUE" \
  --entitlements "$ENTITLEMENTS" \
  "$APP_PATH"

/usr/bin/codesign --verify --strict --verbose=2 "$CONTENTS/MacOS/ClipAllPluginRunner"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"

print "Built $APP_PATH with identity: $SIGNING_IDENTITY"
