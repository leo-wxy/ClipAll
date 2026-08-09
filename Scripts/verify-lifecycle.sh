#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
PLUGIN_PATH="${1:-$PROJECT_ROOT/Plugins/Examples/TimestampTools.clipallplugin}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
OUTPUT_DIR="$PROJECT_ROOT/.build/verification"
MODULE_CACHE="$PROJECT_ROOT/.swift-module-cache"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macosx15.0"

mkdir -p "$OUTPUT_DIR" "$MODULE_CACHE"

swiftc \
  -swift-version 6 \
  -target "$TARGET" \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  "$PROJECT_ROOT"/ClipAll/Domain/*.swift \
  "$PROJECT_ROOT"/ClipAll/PluginHost/Manifest/*.swift \
  "$PROJECT_ROOT"/ClipAll/PluginHost/Validation/*.swift \
  "$PROJECT_ROOT/ClipAll/PluginHost/Installation/PluginInstallationStore.swift" \
  "$PROJECT_ROOT/Verification/PluginLifecycleVerification.swift" \
  -o "$OUTPUT_DIR/plugin-lifecycle-verification"

"$OUTPUT_DIR/plugin-lifecycle-verification" "$PLUGIN_PATH"
