#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
SOURCE_APP="$PROJECT_ROOT/.build/ClipAll.app"
DESTINATION_APP="/Applications/ClipAll.app"
STAGING_APP="/Applications/.ClipAll.app.installing.$$"
BACKUP_APP="${TMPDIR:-/private/tmp}/ClipAll.app.pre-install.$(date +%Y%m%d-%H%M%S)"
EXECUTABLE_PATTERN='^/Applications/ClipAll\.app/Contents/MacOS/ClipAll$'

[[ ! -L "$DESTINATION_APP" ]] || {
  print -u2 "Refusing to replace a symbolic link: $DESTINATION_APP"
  exit 1
}

cleanup() {
  if [[ -e "$STAGING_APP" ]]; then
    rm -rf -- "$STAGING_APP"
  fi
}
trap cleanup EXIT

"$PROJECT_ROOT/Scripts/build-local-app.sh"
test -d "$SOURCE_APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$SOURCE_APP"

/usr/bin/ditto "$SOURCE_APP" "$STAGING_APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$STAGING_APP"

running_pids=("${(@f)$(/usr/bin/pgrep -f "$EXECUTABLE_PATTERN" 2>/dev/null || true)}")
for pid in "${running_pids[@]}"; do
  [[ -n "$pid" ]] && /bin/kill -TERM "$pid"
done

for _ in {1..40}; do
  if ! /usr/bin/pgrep -f "$EXECUTABLE_PATTERN" >/dev/null 2>&1; then
    break
  fi
  /bin/sleep 0.1
done

if /usr/bin/pgrep -f "$EXECUTABLE_PATTERN" >/dev/null 2>&1; then
  print -u2 "ClipAll did not quit; leaving the existing app untouched."
  exit 1
fi

if [[ -e "$DESTINATION_APP" ]]; then
  /bin/mv "$DESTINATION_APP" "$BACKUP_APP"
fi

if ! /bin/mv "$STAGING_APP" "$DESTINATION_APP"; then
  if [[ -e "$BACKUP_APP" && ! -e "$DESTINATION_APP" ]]; then
    /bin/mv "$BACKUP_APP" "$DESTINATION_APP"
  fi
  print -u2 "Installation failed; restored the previous app when available."
  exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$DESTINATION_APP"
/usr/bin/open "$DESTINATION_APP"

print "Installed and launched $DESTINATION_APP"
if [[ -e "$BACKUP_APP" ]]; then
  print "Previous app backup: $BACKUP_APP"
fi
