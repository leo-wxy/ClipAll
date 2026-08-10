#!/bin/zsh

source "${0:A:h}/verification-env.sh"

verification_swiftc \
  "$PROJECT_ROOT/ClipAll/Domain/Identifiers.swift" \
  "$PROJECT_ROOT/ClipAll/Domain/Capability.swift" \
  "$PROJECT_ROOT/ClipAll/Domain/CapabilityOutput.swift" \
  "$PROJECT_ROOT/ClipAll/Domain/CapabilityDescriptor.swift" \
  "$PROJECT_ROOT/ClipAll/Domain/SelectionContext.swift" \
  "$PROJECT_ROOT/ClipAll/Domain/TranslationRequest.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/Security/PluginSecretStore.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/Translation/OpenAICompatibleTranslationProvider.swift" \
  "$PROJECT_ROOT/Verification/OpenAITranslationVerification.swift" \
  -o "$OUTPUT_DIR/openai-translation-verification"

"$OUTPUT_DIR/openai-translation-verification"
