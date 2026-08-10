#!/bin/zsh

source "${0:A:h}/verification-env.sh"

verification_swiftc \
  "$PROJECT_ROOT/ClipAll/Domain/Identifiers.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/Accessibility/ClipboardSelectionFallback.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/Accessibility/PointerSelectionGesture.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/Persistence/SettingsStore.swift" \
  "$PROJECT_ROOT/ClipAll/Features/SelectionOverlay/OverlayPlacement.swift" \
  "$PROJECT_ROOT/Verification/OverlayStateVerification.swift" \
  -o "$OUTPUT_DIR/overlay-state-verification"

"$OUTPUT_DIR/overlay-state-verification"
