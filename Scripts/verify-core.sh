#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
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
  "$PROJECT_ROOT"/ClipAll/Capabilities/ContentFeatureExtractor.swift \
  "$PROJECT_ROOT"/ClipAll/Capabilities/CapabilityRouter.swift \
  "$PROJECT_ROOT"/ClipAll/Capabilities/CapabilityDiscoveryModel.swift \
  "$PROJECT_ROOT"/ClipAll/PluginHost/Manifest/*.swift \
  "$PROJECT_ROOT"/ClipAll/PluginHost/Validation/*.swift \
  "$PROJECT_ROOT"/Verification/CoreVerification.swift \
  -o "$OUTPUT_DIR/core-verification"

"$OUTPUT_DIR/core-verification" "$PROJECT_ROOT/Plugins/Examples/TimestampTools.clipallplugin"
