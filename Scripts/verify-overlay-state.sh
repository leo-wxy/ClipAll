#!/bin/zsh

source "${0:A:h}/verification-env.sh"

verification_swiftc \
  "$PROJECT_ROOT/ClipAll/Domain/Identifiers.swift" \
  "$PROJECT_ROOT/ClipAll/Domain/SelectionContext.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/Accessibility/ClipboardSelectionFallback.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/Accessibility/PointerSelectionGesture.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/Accessibility/SelectionCaptureService.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/Accessibility/SelectionMonitor.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/Persistence/SettingsStore.swift" \
  "$PROJECT_ROOT/ClipAll/Features/SelectionOverlay/OverlayPlacement.swift" \
  "$PROJECT_ROOT/Verification/OverlayStateVerification.swift" \
  -o "$OUTPUT_DIR/overlay-state-verification"

"$OUTPUT_DIR/overlay-state-verification"

verification_swiftc \
  "$PROJECT_ROOT/ClipAll/Domain/Identifiers.swift" \
  "$PROJECT_ROOT/ClipAll/Domain/SelectionContext.swift" \
  "$PROJECT_ROOT/ClipAll/Domain/SupportedDateFormats.swift" \
  "$PROJECT_ROOT/ClipAll/Domain/TranslationRequest.swift" \
  "$PROJECT_ROOT/ClipAll/Domain/PluginConfiguration.swift" \
  "$PROJECT_ROOT/ClipAll/Domain/CapabilityDescriptor.swift" \
  "$PROJECT_ROOT/ClipAll/Domain/CapabilityMatch.swift" \
  "$PROJECT_ROOT/ClipAll/Domain/Capability.swift" \
  "$PROJECT_ROOT/ClipAll/Domain/CapabilityOutput.swift" \
  "$PROJECT_ROOT/ClipAll/Domain/Plugin.swift" \
  "$PROJECT_ROOT/ClipAll/Capabilities/CapabilityRegistry.swift" \
  "$PROJECT_ROOT/ClipAll/Capabilities/ContentFeatureExtractor.swift" \
  "$PROJECT_ROOT/ClipAll/Capabilities/CapabilityRouter.swift" \
  "$PROJECT_ROOT/ClipAll/Capabilities/CapabilityDiscoveryModel.swift" \
  "$PROJECT_ROOT/ClipAll/BuiltInPlugins/Translation/TranslationPlugin.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/Accessibility/PointerSelectionGesture.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/Persistence/SettingsStore.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/Persistence/PluginConfigurationStore.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/Security/PluginSecretStore.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/System/ClipboardService.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/System/PasteService.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/Translation/OpenAICompatibleTranslationProvider.swift" \
  "$PROJECT_ROOT/ClipAll/Features/SelectionOverlay/SelectionOverlayStore.swift" \
  "$PROJECT_ROOT/Verification/OverlayExecutionVerification.swift" \
  -framework Carbon \
  -framework Security \
  -o "$OUTPUT_DIR/overlay-execution-verification"

"$OUTPUT_DIR/overlay-execution-verification"
