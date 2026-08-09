#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
VERSION_FILE="$PROJECT_ROOT/VERSION"
INFO_PLIST="$PROJECT_ROOT/Support/ClipAll-Info.plist"
MAPPER="$PROJECT_ROOT/ClipAll/PluginHost/Manifest/ExternalPluginManifestMapper.swift"
VALIDATOR="$PROJECT_ROOT/ClipAll/PluginHost/Validation/PluginPackageValidator.swift"
EXAMPLE_MANIFEST="$PROJECT_ROOT/Plugins/Examples/TimestampTools.clipallplugin/plugin.json"

[[ -f "$VERSION_FILE" ]] || {
  print -u2 "Missing VERSION file: $VERSION_FILE"
  exit 1
}

VERSION="$(<"$VERSION_FILE")"
if ! print -r -- "$VERSION" | /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  print -u2 "VERSION must be a three-part numeric SemVer: $VERSION"
  exit 1
fi

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST"
}

SHORT_VERSION="$(plist_value CFBundleShortVersionString)"
BUILD_VERSION="$(plist_value CFBundleVersion)"
[[ "$SHORT_VERSION" == "$VERSION" ]] || {
  print -u2 "CFBundleShortVersionString=$SHORT_VERSION does not match VERSION=$VERSION"
  exit 1
}
[[ "$BUILD_VERSION" == "$VERSION" ]] || {
  print -u2 "CFBundleVersion=$BUILD_VERSION does not match VERSION=$VERSION"
  exit 1
}

for path in "$MAPPER" "$VALIDATOR"; do
  /usr/bin/grep -Fq "hostVersion: String = \"$VERSION\"" "$path" || {
    print -u2 "Host version default does not match VERSION in $path"
    exit 1
  }
  if /usr/bin/grep -E 'hostVersion: String = "[0-9]+\.[0-9]+\.[0-9]+"' "$path" |
    /usr/bin/grep -Fv "hostVersion: String = \"$VERSION\"" >/dev/null; then
    print -u2 "Found a stale host version default in $path"
    exit 1
  fi
done

/usr/bin/grep -Fq "\"minimumClipAllVersion\": \"$VERSION\"" "$EXAMPLE_MANIFEST" || {
  print -u2 "TimestampTools minimumClipAllVersion does not match VERSION"
  exit 1
}

print "ClipAll version $VERSION is consistent."
