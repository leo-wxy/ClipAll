#!/bin/zsh

source "${0:A:h}/verification-env.sh"

OUTPUT_DIR="$OUTPUT_DIR/runner-client"
mkdir -p "$OUTPUT_DIR"

verification_swiftc \
  -parse-as-library \
  -module-name ClipAllPluginProtocol \
  -emit-module \
  -emit-module-path "$OUTPUT_DIR/ClipAllPluginProtocol.swiftmodule" \
  -emit-object \
  -o "$OUTPUT_DIR/ClipAllPluginProtocol.o" \
  "$PROJECT_ROOT/ClipAllPluginProtocol/PluginRuntimeProtocol.swift"

verification_swiftc \
  -I "$OUTPUT_DIR" \
  "$PROJECT_ROOT/ClipAll/PluginHost/Runtime/PluginRunnerClient.swift" \
  "$PROJECT_ROOT/Verification/PluginRunnerClientVerification.swift" \
  "$OUTPUT_DIR/ClipAllPluginProtocol.o" \
  -o "$OUTPUT_DIR/plugin-runner-client-verification"

"$OUTPUT_DIR/plugin-runner-client-verification"
