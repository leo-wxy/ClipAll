#!/bin/zsh

source "${0:A:h}/verification-env.sh"

PLUGIN_PATH="${1:-$PROJECT_ROOT/Plugins/Examples/TimestampTools.clipallplugin}"

verification_swiftc \
  "$PROJECT_ROOT"/ClipAll/Domain/*.swift \
  "$PROJECT_ROOT"/ClipAll/PluginHost/Manifest/*.swift \
  "$PROJECT_ROOT"/ClipAll/PluginHost/Validation/*.swift \
  "$PROJECT_ROOT/ClipAll/PluginHost/Installation/PluginInstallationStore.swift" \
  "$PROJECT_ROOT/Verification/PluginLifecycleVerification.swift" \
  -o "$OUTPUT_DIR/plugin-lifecycle-verification"

"$OUTPUT_DIR/plugin-lifecycle-verification" "$PLUGIN_PATH"
