#!/bin/zsh

source "${0:A:h}/verification-env.sh"

verification_swiftc \
  "$PROJECT_ROOT"/ClipAll/Domain/*.swift \
  "$PROJECT_ROOT"/ClipAll/Capabilities/ContentFeatureExtractor.swift \
  "$PROJECT_ROOT"/ClipAll/Capabilities/CapabilityRouter.swift \
  "$PROJECT_ROOT"/ClipAll/Capabilities/CapabilityDiscoveryModel.swift \
  "$PROJECT_ROOT"/ClipAll/PluginHost/Manifest/*.swift \
  "$PROJECT_ROOT"/ClipAll/PluginHost/Validation/*.swift \
  "$PROJECT_ROOT"/Verification/CoreVerification.swift \
  -o "$OUTPUT_DIR/core-verification"

"$OUTPUT_DIR/core-verification" "$PROJECT_ROOT/Plugins/Examples/TimestampTools.clipallplugin"
