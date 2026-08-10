#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
OUTPUT_DIR="$PROJECT_ROOT/.build/verification"
MODULE_CACHE="$PROJECT_ROOT/.swift-module-cache"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macosx15.0"

mkdir -p "$OUTPUT_DIR" "$MODULE_CACHE"

verification_swiftc() {
  swiftc \
    -swift-version 6 \
    -target "$TARGET" \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE" \
    "$@"
}
