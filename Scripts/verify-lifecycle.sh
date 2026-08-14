#!/bin/zsh

source "${0:A:h}/verification-env.sh"

PLUGIN_PATH="${1:-$PROJECT_ROOT/Plugins/Examples/TimestampTools.clipallplugin}"
LIFECYCLE_OUTPUT="$OUTPUT_DIR/lifecycle"
mkdir -p "$LIFECYCLE_OUTPUT"

verification_swiftc \
  -parse-as-library \
  -module-name ClipAllPluginProtocol \
  -emit-module \
  -emit-module-path "$LIFECYCLE_OUTPUT/ClipAllPluginProtocol.swiftmodule" \
  -emit-object \
  -o "$LIFECYCLE_OUTPUT/ClipAllPluginProtocol.o" \
  "$PROJECT_ROOT/ClipAllPluginProtocol/PluginRuntimeProtocol.swift"

verification_swiftc \
  -I "$LIFECYCLE_OUTPUT" \
  "$PROJECT_ROOT"/ClipAll/Domain/*.swift \
  "$PROJECT_ROOT/ClipAll/Capabilities/CapabilityRegistry.swift" \
  "$PROJECT_ROOT/ClipAll/Capabilities/ContentFeatureExtractor.swift" \
  "$PROJECT_ROOT/ClipAll/Capabilities/CapabilityRouter.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/Accessibility/PointerSelectionGesture.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/Persistence/SettingsStore.swift" \
  "$PROJECT_ROOT/ClipAll/Infrastructure/Persistence/PluginConfigurationStore.swift" \
  "$PROJECT_ROOT"/ClipAll/PluginHost/Manifest/*.swift \
  "$PROJECT_ROOT"/ClipAll/PluginHost/Validation/*.swift \
  "$PROJECT_ROOT/ClipAll/PluginHost/Installation/PluginInstallationStore.swift" \
  "$PROJECT_ROOT/ClipAll/PluginHost/Development/DevelopmentPluginStore.swift" \
  "$PROJECT_ROOT/ClipAll/PluginHost/Development/PluginDebugSession.swift" \
  "$PROJECT_ROOT/ClipAll/PluginHost/Runtime/PluginRunnerClient.swift" \
  "$PROJECT_ROOT/ClipAll/PluginHost/Runtime/ExternalPluginExecutor.swift" \
  "$PROJECT_ROOT/ClipAll/PluginHost/Lifecycle/PluginLifecycleController.swift" \
  "$PROJECT_ROOT/Verification/PluginLifecycleVerification.swift" \
  "$LIFECYCLE_OUTPUT/ClipAllPluginProtocol.o" \
  -o "$LIFECYCLE_OUTPUT/plugin-lifecycle-verification"

"$LIFECYCLE_OUTPUT/plugin-lifecycle-verification" "$PLUGIN_PATH"
