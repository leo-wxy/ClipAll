# Backend Quality Guidelines

## Scenario: Sensitive Runner Process I/O

### 1. Scope / Trigger

Apply this contract whenever the host launches a child process whose standard
streams carry selected text, plugin configuration, results, secrets, or other
user-sensitive data. The current owner is
`ClipAll/PluginHost/Runtime/PluginRunnerClient.swift`.

### 2. Signatures

```swift
PluginRunnerClient.execute(
    _ request: PluginRuntimeRequest
) async throws -> PluginRunnerExecution
```

The child process contract remains one JSON request on stdin and one JSON
response on stdout. `PluginRuntimeLimits` owns protocol and byte limits.

### 3. Contracts

- Sensitive request, response, and stderr transport uses anonymous `Pipe`
  instances only. Never stage process standard streams through files.
- Close the host stdin writer after the full request is sent so a runner using
  `readDataToEndOfFile()` receives EOF.
- Drain stdout and stderr while the process is running. Waiting for process
  termination before reading either stream can deadlock on pipe backpressure.
- Retain at most `maximumResponseBytes + 1` bytes from stdout. After crossing
  the limit, continue draining and discard the remainder.
- Drain and discard process stderr. JavaScript debug logs come only from the
  bounded `PluginRuntimeResponse.logs` field; stderr is not a product log.
- Preserve cancellation, timeout, termination, exit-code, response-size, JSON,
  protocol-version, and structural-validation ordering.
- I/O workers must have bounded shutdown. Closing or cancelling a process must
  not leave the caller waiting indefinitely for inherited pipe descriptors.

### 4. Validation & Error Matrix

| Condition | Required result |
| --- | --- |
| Runner is missing or not executable | `PluginRunnerClientError.runnerMissing` |
| Encoded request exceeds `maximumRequestBytes` | `requestTooLarge`; do not launch |
| `Process.run()` fails | `launchFailed` |
| Task is cancelled | terminate the child and throw `CancellationError` |
| Runner exceeds the configured deadline | terminate/SIGKILL fallback, then `timedOut` |
| Runner exits non-zero | `invalidResponse`, before response parsing |
| Successful stdout exceeds `maximumResponseBytes` | `responseTooLarge` |
| stdout is empty, invalid JSON, wrong protocol, or structurally inconsistent | `invalidResponse` |
| stdin writer receives EPIPE after child exit | keep the exit/response error semantics; do not add a public error |

### 5. Good / Base / Bad Cases

- Good: write request data through stdin Pipe, close for EOF, concurrently
  drain bounded stdout and discard stderr, then validate the response.
- Base: a small valid response exits successfully and preserves duration and
  `PluginRuntimeResponse.logs` behavior.
- Bad: use `temporaryDirectory`, `stdin.json`, `stdout.json`, or `stderr.log`
  for process transport, even when permissions are restrictive or cleanup is
  scheduled.
- Bad: merge stderr into stdout, because stdout owns exactly one JSON response.
- Bad: stop reading stdout immediately after the limit is crossed; the child
  can block before it exits.

### 6. Tests Required

- `Scripts/verify-runner-client.sh` must assert:
  - stdin EOF completes a valid runner request;
  - no `ClipAllPluginRunner-*` transport directory appears while running;
  - simultaneous oversized stdout and stderr do not deadlock;
  - cancellation under output pressure completes in under one second;
  - existing missing, invalid, non-zero, oversized, timeout, cancellation, and
    request-too-large errors remain stable.
- `Scripts/verify-plugin.sh` must pass all real runner fixtures.
- `Scripts/verify-all.sh` and SwiftPM build/test must pass before commit.
- Static review of `PluginRunnerClient.swift` must find no process transport
  file paths or `FileManager.default.temporaryDirectory` usage.

### 7. Wrong vs Correct

#### Wrong

`try requestData.write(to: temporaryURL)`

#### Correct

`process.standardInput = Pipe()`

## Scenario: Plugin Runtime Configuration API v2

### 1. Scope / Trigger

Apply this contract when changing external plugin manifests, Runner request
DTOs, JavaScript handler arguments, plugin configuration, or uninstall data
cleanup.

### 2. Signatures

```swift
PluginRuntimeInput(
    pluginID: PluginID,
    text: String,
    configuration: [String: PluginRuntimeConfigurationValue]
)

PluginLifecycleController.uninstall(pluginID: PluginID) async throws
```

```javascript
const configuration = App.getPluginEnv(pluginID)
ClipAllPlugin.handler = function (text) { /* ... */ }
```

Both `manifestVersion` and `PluginRuntimeLimits.protocolVersion` are `2`.

### 3. Contracts

- A handler receives selected text as its only argument. Configuration, locale,
  timezone, and host objects are not handler parameters.
- `App.getPluginEnv(id)` accepts only the currently executing stable plugin ID
  and returns the launch-time resolved configuration snapshot.
- The snapshot contains declared non-secret fields only, merges manifest
  defaults with user overrides, filters stale fields, and is recursively frozen.
- `PluginConfigurationStore` remains the single ordinary-configuration source
  for settings, built-in capabilities, external execution, and the debugger.
- The Runner exposes no raw request global and gains no file, network,
  pasteboard, Accessibility, Keychain, or configuration-write capability.
- Disabling, upgrading, and reloading preserve configuration. Uninstall removes
  plugin-scoped Keychain accounts before package mutation and removes ordinary
  configuration after package removal succeeds.
- Only the bundled TimestampTools package may automatically replace an
  installed v1 copy. Other v1 manifests remain invalid.

### 4. Validation & Error Matrix

| Condition | Required result |
| --- | --- |
| Manifest version is not 2 | `manifest_version` at `$.manifestVersion` |
| Runner protocol is not 2 | `unsupported_protocol` before v2 DTO decoding |
| `getPluginEnv` receives another or empty ID | deterministic plugin-ID error |
| Plugin has no configuration | return frozen `{}` |
| Field is secret, unknown, or removed | never include it in the snapshot |
| Configuration field type is invalid | reject the field write |
| Keychain enumeration/deletion fails | abort uninstall before registry/package mutation |
| Package removal fails | retain ordinary configuration |
| Uninstall succeeds | delete capability references, state, ordinary config, and secrets |

### 5. Good / Base / Bad Cases

- Good: `handler(text)` reads its own frozen environment through
  `App.getPluginEnv("com.example.plugin")`.
- Base: a plugin with no fields receives `{}` and returns a normal result.
- Good: changing one setting preserves sibling fields and is visible to the
  next formal execution and debugger execution.
- Bad: pass the whole request object to JavaScript or expose
  `globalThis.__clipallRequest`.
- Bad: retain plugin configuration after uninstall or silently swallow a
  Keychain cleanup failure.

### 6. Tests Required

- `Scripts/verify-plugin.sh` asserts string handler input, own-ID access,
  cross-ID rejection, frozen snapshots, hidden raw request, and real fixtures.
- `Scripts/verify-runner-client.sh` asserts a real v1 request returns
  `unsupported_protocol` and keeps process failure limits stable.
- `Scripts/verify-overlay-state.sh` asserts defaults, sibling isolation, type
  rejection, stale/secret filtering, and ordinary configuration removal.
- `Scripts/verify-lifecycle.sh` asserts exact plugin-ID secret cleanup,
  failure-before-mutation ordering, and successful uninstall cleanup.
- `Scripts/verify-core.sh`, `Scripts/verify-all.sh`, and
  `swift build --target ClipAll` must pass before commit.

### 7. Wrong vs Correct

#### Wrong

```javascript
function handler(request) {
  return request.configuration.mode
}
```

#### Correct

```javascript
function handler(text) {
  const mode = App.getPluginEnv("com.example.plugin").mode
  return { title: text, subtitle: mode, items: [] }
}
```

## Scenario: Cross-App Pointer Selection Fallback

### 1. Scope / Trigger

Apply this contract when changing pointer gesture detection, Accessibility
selection capture, hit-element classification, or the automatic clipboard
fallback. The current owners are:

- `ClipAll/Infrastructure/Accessibility/PointerSelectionGesture.swift`
- `ClipAll/Infrastructure/Accessibility/SelectionMonitor.swift`
- `ClipAll/Infrastructure/Accessibility/SelectionCaptureService.swift`
- `ClipAll/Infrastructure/Accessibility/ClipboardSelectionFallback.swift`
- `ClipAll/Infrastructure/Persistence/SettingsStore.swift`

### 2. Signatures

```swift
SelectionCaptureService.captureCurrentSelection(
    triggerLocation: CGPoint,
    fallbackPolicy: SelectionFallbackPolicy
) async throws -> SelectionContext

SelectionHitClassifier.allowsClipboardFallback(
    in path: [SelectionHitEvidenceNode]
) -> Bool

SettingsStore.allowsAutomaticDisplay(
    for intent: PointerSelectionIntent,
    bundleIdentifier: String?
) -> Bool

SelectionMonitor.capturePointerSelection(
    _ intent: PointerSelectionIntent,
    sourceBundleIdentifier: String?,
    after delay: Duration,
    requiresRunning: Bool
)
```

`PointerSelectionIntent.fallbackPolicy` owns the gesture policy:

- drag -> `textHitRequired`
- multi-click -> `textHitRequired`
- shift-click -> `disabled`

### 3. Contracts

- Try bounded AX selection capture before clipboard fallback. AX success never
  sends `Command-C`.
- A normal single click has no pointer selection intent and never captures.
- Global drag and multi-click switches default to enabled. Per-App automatic
  display policy is `followGlobal`, `dragOnly`, or `disabled`; it affects pointer
  capture only. Registered hotkey and menu capture bypass the pointer policy.
- Apply the automatic display policy before AX or clipboard work. Re-check the
  frontmost bundle after the settle delay and after capture; if it differs from
  the mouse-up source, invalidate without publishing the new App's selection.
- For multi-click AX results with selection bounds, require the trigger point to
  intersect those bounds with the existing drag-distance tolerance. A focused
  element may retain a stale non-empty AX selection after the user clicks elsewhere.
- Automatic drag remains compatible on AX-opaque targets. Multi-click may use
  compatible copy for a truly empty hit path or a custom child path without hard
  control evidence, but a root-only `AXWindow` / `AXApplication` path rejects
  before synthetic `Command-C` because it cannot tie focused text to the click.
- Any blocking role/action rejects fallback. Scan the complete bounded path so
  a text-like child cannot hide an ancestor `AXRow`, Tab, button, or menu item.
- A non-empty custom-child path without selection semantics may proceed only
  under `.compatiblePointer`; `.textHitRequired` still rejects it.
- A path with selection attributes, or number-of-characters plus visible-range
  semantics, allows fallback when no blocking node exists.
- Do not add bundle-specific allowlists or fixed AX settle delays for an App
  whose hit path is empty.
- Selected text and pasteboard contents remain memory-only and never enter
  logs. Logging may include trigger, policy, result source, error enum, and
  bundle identifier.
- Snapshot a real `NSPasteboard` through the native Pasteboard Manager API so
  private flavors are preserved as bytes plus flavor flags. Restore the original
  item ordering and flavors while the transaction still owns the generation;
  never stage the snapshot through a file.
- AX-visible secure text fields reject capture. For an AX-invisible surface,
  fallback can only consume pure text that the source App supplies in response
  to the explicit user `Command-C`; users retain global and per-App controls.

### 4. Validation & Error Matrix

| Trigger / evidence | Required behavior |
| --- | --- |
| Normal single click | Do not capture or send copy |
| Global pointer trigger disabled | Invalidate before AX or clipboard work |
| App policy is `dragOnly` | Allow drag/Shift-click; reject multi-click |
| App policy is `disabled` | Reject every pointer trigger; allow hotkey/menu capture |
| Frontmost App changes during settle/capture | Invalidate; publish nothing from the new App |
| AX selection succeeds | Publish AX selection; do not send copy |
| Multi-click AX bounds do not contain the trigger point | Invalidate as a stale focused selection |
| Drag + text AX hit path | Try constrained clipboard fallback |
| Drag + empty hit path | Try compatible copy and validate the result |
| Drag + known non-text hit path | Suppress before sending copy |
| Multi-click + empty AX hit path | Try compatible copy and validate the result |
| Multi-click + only `AXWindow` / `AXApplication` | Suppress before sending copy |
| Multi-click + text path | Try constrained clipboard fallback |
| Multi-click + blocking role/action | Suppress before sending copy |
| Multi-click + custom child path without blockers | Try compatible copy and validate the result |
| Shift-click + AX failure | Suppress clipboard fallback |
| Clipboard returns empty, times out, or contains a non-text object | Restore safely and publish nothing |
| Clipboard changes concurrently | Preserve the newer external content |
| Existing clipboard contains an AppKit-unreadable private flavor | Snapshot and restore its native bytes and flags |

### 5. Good / Base / Bad Cases

- Good: POPO exposes no focused or hit AX element; compatible pointer capture
  validates its copied result, while explicit hotkey/menu capture remains available.
- Good: an IDE file-node hit exposes only `AXWindow -> AXApplication`; multi-click
  suppresses fallback instead of copying a retained editor selection.
- Base: VSCode / VSCodium text surfaces expose selection semantics and continue
  to work.
- Good: IDE file-tree rows and Tabs expose blocking or non-text evidence and
  are rejected before fallback.
- Good: a disabled App is rejected before `SelectionCapturing` is called, while
  the same App remains available through the explicit hotkey or menu command.
- Good: a Qt private image-path flavor survives a successful text fallback
  byte-for-byte without the selected text touching disk.
- Bad: send a synthetic copy when an automatic pointer trigger has no positive
  text-selection evidence.
- Bad: allow any non-empty hit path without checking its complete ancestry.
- Bad: special-case a bundle identifier or add a fixed delay instead of using
  observable AX evidence.

### 6. Tests Required

- `Scripts/verify-overlay-state.sh` must assert:
  - empty hit paths allow compatible drag and multi-click fallback;
  - root-only `AXWindow` / `AXApplication` paths reject multi-click fallback;
  - known text surfaces allow fallback;
  - image, file-tree, Tab, button, and non-empty non-text paths reject fallback;
  - drag, multi-click, shift-click, and normal-click policies remain stable;
  - global and per-App policy defaults, persistence, deletion, and invalid-value
    sanitization remain stable;
  - policy rejection invokes no capture, source switching invalidates, and
    hotkey/menu capture bypasses the pointer policy;
  - multi-click publishes AX bounds that contain the trigger point and rejects
    stale AX bounds elsewhere;
  - a private native flavor is restored byte-for-byte after successful fallback;
  - file/image/dynamic-object clipboard payloads remain rejected and snapshots
    retain their existing restoration and concurrency behavior.
- `Scripts/verify-all.sh` and `swift build --target ClipAll` must pass.
- If a restricted agent sandbox makes the real `PasteboardCreate` fixture fail
  before its assertions run, rerun the unchanged verification script outside
  that sandbox. Treat it as a product regression only when the unrestricted run
  also fails; never skip the private-flavor assertions or patch capture code to
  accommodate the sandbox.
- Before commit, install through `Scripts/install-local-app.sh` and manually
  verify one AX-invisible text App, one Chromium editor, one IDE file tree / Tab,
  and one input field.
- Static search must find no temporary selection-text logging or diagnostic
  probe in product code.

### 7. Wrong vs Correct

#### Wrong

```swift
// Empty means AX supplied no evidence, not that the pointer selected text.
guard !path.isEmpty else { return true }
```

#### Correct

```swift
guard !path.isEmpty else { return false }
```
