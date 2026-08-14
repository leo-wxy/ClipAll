# Runtime Contract Inventory

## Current Flow

```text
SelectionContext.normalizedText
  -> ExternalPluginExecutor
  -> PluginRuntimeRequest.input
  -> PluginRunnerClient JSON
  -> ClipAllPluginRunner
  -> JavaScriptPluginRuntime
  -> ClipAllPlugin[handler](request)
```

- `PluginRuntimeInput` currently contains `text`, `configuration`,
  `localeIdentifier`, and `systemTimeZoneIdentifier`
  (`ClipAllPluginProtocol/PluginRuntimeProtocol.swift:48-65`).
- Production configuration comes from
  `PluginConfigurationStore.resolvedValues(pluginID:)`; locale and time zone come
  from system closures (`ClipAll/PluginHost/Runtime/ExternalPluginExecutor.swift:45-100`).
- The Runner exposes the complete input as global `__clipallRequest`, freezes it,
  and calls the handler with that object
  (`ClipAllPluginRunner/JavaScriptPluginRuntime.swift:27-65,160-194`).
- The debugger and fixture path independently builds the same DTO
  (`ClipAll/PluginHost/Development/PluginDebugSession.swift:93-177`).

## Compatibility Finding

- `manifestVersion` is currently fixed to 1 in
  `ExternalPluginManifestMapper.swift:42-45`.
- Runner requests and responses are fixed to `protocolVersion == 1` in
  `PluginRuntimeProtocol.swift` and checked by both Runner and host.
- Changing only the JavaScript call from `handler(request)` to `handler(text)`
  cannot identify an old script before execution. A source compatibility shim or
  source inspection would be ambiguous and was explicitly rejected by the product
  decision.
- The existing architecture contract requires incompatible manifest or Runner
  changes to increase `manifestVersion` or `protocolVersion`
  (`Docs/Architecture.md:103-108`).
- Runner `main.swift` currently decodes the complete request before the Runtime
  protocol guard. After adding a required pluginID, a raw v1 JSON request would
  otherwise fail as `invalid_request`; v2 needs a protocol-only envelope probe
  before decoding the full DTO.
- An installed bundled TimestampTools v1 package becomes `manifest_version`
  invalid. The existing bundled repair path only recognizes `incompatible_host`
  (`PluginLifecycleController.swift:132-143`), so that exact sample needs an
  explicit v2 replacement path without enabling general v1 compatibility.

## Minimal v2 Boundary

- Set manifest and Runner protocol versions to 2.
- Decode a minimal protocol envelope first so raw v1 JSON deterministically returns
  `unsupported_protocol`.
- Keep the internal process request as JSON, carrying only current plugin ID,
  selected text, non-secret configuration snapshot, script metadata, and log flag.
- Call JavaScript handlers with the selected text string only.
- Install an immutable `App.getPluginEnv(pluginID)` closure before evaluating the
  plugin script; do not expose the raw internal request as a global object.
- Remove locale/timezone DTO fields. TimestampTools can use standard `Intl` / `Date`
  behavior for the machine environment.
- Allow the bundled TimestampTools repair path to replace its own v1 installation;
  reject all other v1 packages normally.

## Required Synchronization

- Swift protocol DTO and version constant.
- JavaScript Runner bootstrap and handler invocation.
- Production executor and developer debugger request construction.
- Manifest mapper, machine-readable schema, SDK documentation, example manifest,
  example script, fixtures, and verification programs.
