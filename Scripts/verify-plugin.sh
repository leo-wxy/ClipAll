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

env \
  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
  swift build \
    --package-path "$PROJECT_ROOT" \
    --scratch-path "$PROJECT_ROOT/.build" \
    --disable-sandbox \
    --build-system native \
    --product ClipAllPluginRunner

swiftc \
  -swift-version 6 \
  -target "$TARGET" \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  "$PROJECT_ROOT/ClipAllPluginProtocol/PluginRuntimeProtocol.swift" \
  "$PROJECT_ROOT/Verification/PluginRuntimeVerification.swift" \
  -o "$OUTPUT_DIR/plugin-runtime-verification"

"$OUTPUT_DIR/plugin-runtime-verification" \
  "$PLUGIN_PATH" \
  "$PROJECT_ROOT/.build/${ARCH}-apple-macosx/debug/ClipAllPluginRunner"
