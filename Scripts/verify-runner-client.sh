#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
OUTPUT_DIR="$PROJECT_ROOT/.build/verification/runner-client"
MODULE_CACHE="$PROJECT_ROOT/.swift-module-cache"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macosx15.0"

mkdir -p "$OUTPUT_DIR" "$MODULE_CACHE"

swiftc \
  -swift-version 6 \
  -target "$TARGET" \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  -parse-as-library \
  -module-name ClipAllPluginProtocol \
  -emit-module \
  -emit-module-path "$OUTPUT_DIR/ClipAllPluginProtocol.swiftmodule" \
  -emit-object \
  -o "$OUTPUT_DIR/ClipAllPluginProtocol.o" \
  "$PROJECT_ROOT/ClipAllPluginProtocol/PluginRuntimeProtocol.swift"

swiftc \
  -swift-version 6 \
  -target "$TARGET" \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  -I "$OUTPUT_DIR" \
  "$PROJECT_ROOT/ClipAll/PluginHost/Runtime/PluginRunnerClient.swift" \
  "$PROJECT_ROOT/Verification/PluginRunnerClientVerification.swift" \
  "$OUTPUT_DIR/ClipAllPluginProtocol.o" \
  -o "$OUTPUT_DIR/plugin-runner-client-verification"

"$OUTPUT_DIR/plugin-runner-client-verification"
