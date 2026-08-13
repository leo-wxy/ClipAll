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

- drag -> `enabled`
- multi-click -> `rejectKnownNonText`
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
- For multi-click, an empty hit path means AX cannot classify the surface; it
  may continue to the existing constrained clipboard fallback.
- Any blocking role/action rejects fallback. Scan the complete bounded path so
  a text-like child cannot hide an ancestor `AXRow`, Tab, button, or menu item.
- A non-empty path with no selection semantics rejects fallback.
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
| Drag + fallback-eligible AX failure | Try constrained clipboard fallback |
| Multi-click + empty AX hit path | Try constrained clipboard fallback |
| Multi-click + text path | Try constrained clipboard fallback |
| Multi-click + blocking role/action | Suppress before sending copy |
| Multi-click + non-empty path without selection semantics | Suppress before sending copy |
| Shift-click + AX failure | Suppress clipboard fallback |
| Clipboard returns empty, times out, or contains a non-text object | Restore safely and publish nothing |
| Clipboard changes concurrently | Preserve the newer external content |
| Existing clipboard contains an AppKit-unreadable private flavor | Snapshot and restore its native bytes and flags |

### 5. Good / Base / Bad Cases

- Good: POPO exposes no focused or hit AX element; explicit multi-click enters
  the existing clipboard fallback and publishes its pure-text result.
- Base: VSCode / VSCodium text surfaces expose selection semantics and continue
  to work.
- Good: IDE file-tree rows and Tabs expose blocking or non-text evidence and
  are rejected before fallback.
- Good: a disabled App is rejected before `SelectionCapturing` is called, while
  the same App remains available through the explicit hotkey or menu command.
- Good: a Qt private image-path flavor survives a successful text fallback
  byte-for-byte without the selected text touching disk.
- Bad: treat an empty AX path as proof that the pointer target is non-text.
- Bad: allow any non-empty hit path without checking its complete ancestry.
- Bad: special-case a bundle identifier or add a fixed delay instead of using
  observable AX evidence.

### 6. Tests Required

- `Scripts/verify-overlay-state.sh` must assert:
  - empty hit paths allow constrained fallback;
  - known text surfaces allow fallback;
  - file-tree, Tab, button, and non-empty non-text paths reject fallback;
  - drag, multi-click, shift-click, and normal-click policies remain stable;
  - global and per-App policy defaults, persistence, deletion, and invalid-value
    sanitization remain stable;
  - policy rejection invokes no capture, source switching invalidates, and
    hotkey/menu capture bypasses the pointer policy;
  - a private native flavor is restored byte-for-byte after successful fallback;
  - file/image/dynamic-object clipboard payloads remain rejected and snapshots
    retain their existing restoration and concurrency behavior.
- `Scripts/verify-all.sh` and `swift build --target ClipAll` must pass.
- Before commit, install through `Scripts/install-local-app.sh` and manually
  verify one AX-invisible text App, one Chromium editor, one IDE file tree / Tab,
  and one input field.
- Static search must find no temporary selection-text logging or diagnostic
  probe in product code.

### 7. Wrong vs Correct

#### Wrong

```swift
// Empty means AX supplied no evidence, not that the surface is non-text.
guard !path.isEmpty else { return false }
```

#### Correct

```swift
guard !path.isEmpty else { return true }
```
