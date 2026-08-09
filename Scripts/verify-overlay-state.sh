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
  "$PROJECT_ROOT/ClipAll/Domain/Identifiers.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/Persistence/SettingsStore.swift" \
  "$PROJECT_ROOT/ClipAll/Features/SelectionOverlay/OverlayPlacement.swift" \
  "$PROJECT_ROOT/Verification/OverlayStateVerification.swift" \
  -o "$OUTPUT_DIR/overlay-state-verification"

"$OUTPUT_DIR/overlay-state-verification"
