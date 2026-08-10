#!/bin/zsh

source "${0:A:h}/verification-env.sh"

PLUGIN_PATH="${1:-$PROJECT_ROOT/Plugins/Examples/TimestampTools.clipallplugin}"

env \
  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
  swift build \
    --package-path "$PROJECT_ROOT" \
    --scratch-path "$PROJECT_ROOT/.build" \
    --disable-sandbox \
    --build-system native \
    --product ClipAllPluginRunner

verification_swiftc \
  "$PROJECT_ROOT/ClipAllPluginProtocol/PluginRuntimeProtocol.swift" \
  "$PROJECT_ROOT/Verification/PluginRuntimeVerification.swift" \
  -o "$OUTPUT_DIR/plugin-runtime-verification"

"$OUTPUT_DIR/plugin-runtime-verification" \
  "$PLUGIN_PATH" \
  "$PROJECT_ROOT/.build/${ARCH}-apple-macosx/debug/ClipAllPluginRunner"
