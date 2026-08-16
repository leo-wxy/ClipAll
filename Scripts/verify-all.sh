#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
PLUGIN_PATH="${1:-$PROJECT_ROOT/Plugins/Examples/TimestampTools.clipallplugin}"

print "==> verify-product-structure"
if /usr/bin/grep -REn 'CapabilityCenter|capability-center|能力中心' \
  "$PROJECT_ROOT/ClipAll" \
  "$PROJECT_ROOT/Docs/Architecture.md"; then
  print -u2 "独立能力中心不得重新进入当前产品结构"
  exit 1
fi

if ! /usr/bin/grep -Fq 'setPinned(capability.id, isPinned:' \
  "$PROJECT_ROOT/ClipAll/Features/PluginManagement/PluginsSettingsView.swift"; then
  print -u2 "插件详情必须保留能力固定入口"
  exit 1
fi

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
