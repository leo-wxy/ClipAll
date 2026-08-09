#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
PLUGIN_PATH="${1:-$PROJECT_ROOT/Plugins/Examples/TimestampTools.clipallplugin}"

checks=(
  verify-core.sh
  verify-overlay-state.sh
  verify-openai-translation.sh
  verify-runner-client.sh
)

for check in "${checks[@]}"; do
  print "==> $check"
  "$PROJECT_ROOT/Scripts/$check"
done

print "==> verify-plugin.sh"
"$PROJECT_ROOT/Scripts/verify-plugin.sh" "$PLUGIN_PATH"

print "==> verify-lifecycle.sh"
"$PROJECT_ROOT/Scripts/verify-lifecycle.sh" "$PLUGIN_PATH"

print "All ClipAll verifications passed."
