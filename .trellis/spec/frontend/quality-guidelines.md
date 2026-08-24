# Frontend Quality Guidelines

## Required Checks

- `swift build --target ClipAll` must compile the full application module.
- `Scripts/verify-overlay-state.sh` must pass for every overlay geometry change.
- Light and dark appearances require a screenshot of the installed Applications
  copy when shared colors, surfaces, or window chrome change.
- Pointer hover, pressed state, keyboard focus, and non-color status text must be
  checked for every new interactive row.

## Selection Overlay Contract

- The overlay width is fixed at 324 points in compact and expanded states.
- Ordinary mode stays a non-activating `NSPanel`; only the search state accepts
  keyboard input.
- Expanding discovery must not automatically focus the search field or call
  `makeKey()`. Keep `becomesKeyOnlyIfNeeded` enabled so an explicit click in the
  search field requests keyboard focus without rebuilding TextInputUI while the
  user is only browsing results.
- Initial placement is selection-bounds first and pointer fallback second.
- Resizing always preserves the visual top edge (`maxY`) so the compact action
  bar stays fixed and additional content expands downward. If the screen has
  insufficient room below, clamp the expanded height instead of moving the bar.
- Capture the actual `panel.frame` top-left after first presentation and reuse it
  for that selection context.
- Compact panel height must equal the action bar's measured 36-point height. A
  40-point minimum centers the 36-point bar at `y = 2`, while expanded content
  starts it at `y = 0`, producing a visible two-point up/down jump.
- A user-triggered expansion or collapse must update SwiftUI content state and
  the `NSPanel` frame synchronously in one coordinator-owned main-thread turn.
  Do not resize on a later task turn or replace the hosting root; either exposes
  an empty intermediate frame as a disappear/rebuild flash and root replacement
  also discards the plus-button rotation transition.
- The discovery list fits its visible rows and empty state, capped at 176 points;
  it must not claim the full cap when the content is shorter, and it may shrink
  below its ideal height when the anchored panel reaches a screen boundary.
- Result content uses its natural height when it fits. At a screen boundary it
  becomes internally scrollable instead of clipping cards or moving the panel's
  top edge.
- Copy success dismisses immediately. New visual animation must not delay the
  store's dismissal or intercept source-app key events.
- While the overlay is visible, register Escape as a temporary Carbon hot key;
  unregister it synchronously whenever the panel hides. This closes compact and
  expanded states without making the non-activating panel key.
- Every Carbon hot-key handler must validate the event's `EventHotKeyID` before
  acting, so Escape cannot trigger selection capture and the configured capture
  shortcut cannot dismiss the overlay.
- Do not implement Escape dismissal with an `NSEvent.keyDown` monitor. Ordinary
  keyboard events must stay in the source App to preserve IME composition and
  prevent duplicated input.

## Scenario: External Capability Dismissal

### 1. Scope / Trigger

- Apply this contract when a capability opens another application or performs a
  side effect that does not render a result inside the overlay.

### 2. Signatures

- `CapabilityExecuting.executionPresentation` returns `.overlay` by default.
- Capabilities such as `SearchCapability` that return `CapabilityOutput.external`
  declare `.external` explicitly.

### 3. Contracts

- `SelectionOverlayStore.execute` must set `isVisible = false` before starting
  an external executor. It must not enter `.executing`, a transient message, or
  any other phase that changes panel height.
- `SelectionOverlayCoordinator` observes `store.$isVisible`; a `false` value
  cancels pending geometry synchronization and calls `orderOut` synchronously.
- External success records recent use. Failure logs only capability and error
  types and never recreates the dismissed context or logs selected text.

### 4. Validation & Error Matrix

| Condition | Required result |
|---|---|
| External executor starts | Store and panel are already hidden |
| External output succeeds | Record recent use; do not reopen overlay |
| External executor fails | Log structural metadata only; stay hidden |
| `.external` executor returns an overlay output | Log contract violation; stay hidden |
| `.overlay` executor returns `.external` | Show a contract failure in the existing overlay |

### 5. Good / Base / Bad Cases

- Good: Search hides the panel in the button event turn, then opens the browser.
- Base: Translation remains `.overlay` and keeps its progress/result UI.
- Bad: Set `.executing`, open the browser, show a 650ms success message, and
  dismiss afterward; the intermediate relayout is visible as a jump.

### 6. Tests Required

- `Verification/OverlayExecutionVerification.swift` asserts synchronous Store
  dismissal, `.ready` phase, hidden-before-execute ordering, one execution, and
  recent-use recording.
- Manual QA uses `/Applications/ClipAll.app` and checks that Search disappears
  in place before the browser activates.

### 7. Wrong vs Correct

#### Wrong

```swift
phase = .executing(capabilityID)
let output = try await executor.execute(in: context)
showTransientMessage("Opened", dismissAfter: true)
```

#### Correct

```swift
if executor.executionPresentation == .external {
    dismiss()
    executionTask = Task { try await executor.execute(in: context) }
}
```

## Scenario: Cross-App Selection Trigger And Capture

### 1. Scope / Trigger

- Apply this contract whenever automatic pointer selection, the global shortcut,
  or `SelectionCaptureService` changes.
- The contract prevents stale highlighted text from reopening the overlay and
  supports custom controls or WebViews that do not expose a system-wide focused
  element.

### 2. Signatures

- `PointerSelectionGesture.begin(at:)` starts one pointer gesture.
- `PointerSelectionGesture.update(at:)` records whether movement reaches the
  four-point drag threshold.
- `PointerSelectionGesture.end(at:clickCount:isShiftPressed:) -> PointerSelectionIntent?`
  returns `.drag`, `.multiClick`, `.shiftClick`, or `nil` and always resets state.
- `PointerSelectionIntent.fallbackPolicy` maps `.drag` to `.compatiblePointer`,
  `.multiClick` to `.textHitRequired`, and `.shiftClick` to `.disabled`.
- `SelectionAutomaticDisplayPolicy` is `followGlobal`, `dragOnly`, or `disabled`.
- `SettingsStore.allowsAutomaticDisplay(for:bundleIdentifier:)` is the single
  global/per-App pointer-policy decision.
- `SelectionCapturing.preflightFallbackPolicy(for:at:)` classifies the original
  second mouse-down target before a multi-click can replace it with new UI.
- `SelectionHitClassifier.multiClickFallbackPolicy(in:hasTextSelectionCursor:)`
  combines the original AX hit path with the system I-beam signal.
- The async `SelectionCapturing.captureCurrentSelection(triggerLocation:fallbackPolicy:)`
  is the single capture entry used by pointer, registered hotkey, and menu commands.

### 3. Contracts

- Pointer auto-capture runs only after a drag at least four points, a mouse-up
  with `clickCount >= 2`, or Shift-click. A plain click never reads a retained
  old selection.
- Settings opens on the dedicated `取词` section. It owns the monitoring master,
  drag and multi-click switches, per-App policy, fixed-filter explanation, and
  compatibility fallback. The floating panel and menu bar do not edit these
  preferences.
- New global trigger switches default to enabled. An added App defaults to
  `followGlobal`; deleting its row removes both automatic-display policy and
  compatibility-fallback exclusion. Legacy fallback exclusions remain
  fallback-only and appear in the same App list.
- Gate pointer capture before AX/clipboard work, then re-check the mouse-up
  source bundle after the settle delay and after capture. Hotkey and menu
  capture bypass the pointer policy.
- Keyboard selection is explicit: the Carbon-registered global shortcut may
  capture, but ordinary `NSEvent.keyDown` must never be monitored or replayed.
- Resolve AX candidates in this order: system-wide focus, frontmost application
  focus, then element-at-pointer. For each candidate, inspect a bounded ancestor
  chain for standard selected text/range and Text Marker selection.
- If AX fails after pointer drag, registered hotkey, or menu capture,
  compatibility capture may send one targeted `⌘C` only when enabled and the
  source bundle is not excluded. A drag that crosses the movement threshold is
  a compatible selection intent: it may continue without AX text semantics,
  but known control roles/actions and images are rejected before copying, and
  the copied item must still pass the text-only clipboard checks. Multi-click
  starts as `textHitRequired`, then preflights the original second mouse-down
  path. A non-empty custom text path without hard roles/actions may use
  `.compatiblePointer`. If the AX path is empty, only a current system cursor
  whose image data and hot spot match `NSCursor.iBeam` is positive text evidence;
  another or unavailable cursor remains strict. Never classify cursors with a
  logged image hash, dimensions, a bundle whitelist, or one App's sampled values.
  An explicit image/control path and a missing second-mouse-down preflight also
  remain strict. Capture must use the original mouse-up location rather than the
  cursor's later position. `AXShowMenu` alone is not a blocker
  because Electron text surfaces expose it together with real selection semantics.
  Shift-click is AX-only.
- Clipboard fallback snapshots all readable pasteboard items before clearing,
  waits asynchronously for a new change count, and restores only while it still
  owns the current generation. A later external write must never be overwritten.
- A real `NSPasteboard` snapshot uses native flavor bytes and flags so private
  Qt/AppKit-unreadable types can be restored without writing them to disk.
- Before reading a string representation, clipboard fallback rejects a new item
  containing file URLs, file lists, Finder node references, promised-file,
  image, audio/video, PDF, archive, vCard, or font types, then restores the
  owned clipboard generation. Dynamic UTIs must also be decoded through their
  `com.apple.nspboard-type` tags before classification; comparing only the
  outer `dyn.*` identifier is insufficient.
- Secure text fields fail with `secureInput` and never enter clipboard fallback.
  Selected text is never written to diagnostics; logs may contain only trigger
  type, AX role, error type, and bounds presence.

### 4. Validation & Error Matrix

| Condition | Required result |
|---|---|
| Single click with retained highlight | No capture and no overlay |
| Global multi-click switch off | Double/triple click does not capture; drag remains independent |
| App policy `dragOnly` | Reject multi-click and allow drag/Shift-click |
| App policy `disabled` | Reject pointer capture; keep hotkey/menu capture available |
| Frontmost App changes after mouse-up | Invalidate before publishing any selection |
| Drag below four points | No capture |
| Drag at least four points | Capture after the short selection-settle delay |
| Drag over an AX-opaque custom text surface or empty hit path | Try compatibility copy; publish only validated text and restore the clipboard |
| Drag over a known image/control target | Reject before `⌘C`; preserve the clipboard |
| Drag copy produces a typed non-text object | Reject and restore; no overlay |
| Double/triple click with AX text | Capture after mouse-up without fallback |
| Double/triple click with an opaque custom-text preflight path | Try compatible copy using the original pointer location |
| Double/triple click with an empty AX path and native I-beam | Try compatible copy; publish only validated non-empty text |
| Double/triple click with an empty AX path and arrow/unavailable cursor | Keep `textHitRequired`; reject before `⌘C` |
| Double/triple click whose original target is image/control | Keep `textHitRequired`; reject before `⌘C` |
| Double/triple click with no second-mouse-down preflight | Keep `textHitRequired`; reject before `⌘C` |
| VSCode text path with selection attributes and `AXShowMenu` | Accept after the complete path has no hard control role |
| Double/triple click on an IDE tab while editor text remains selected | Reject before `⌘C`; never publish stale editor text |
| Double/triple click on a typed non-text object | Reject copied object; no overlay |
| Shift-click with AX text | Capture after mouse-up without fallback |
| Shift-click on a non-text object | No `⌘C`; no overlay |
| Registered hotkey | Capture without pointer-gesture state |
| Missing system-wide focus | Try frontmost-app focus, then pointer hit-test |
| Text Marker selection only | Resolve text locally; bounds may fall back to pointer |
| AX unsupported, fallback enabled | Temporarily copy, restore, and publish a new context |
| Fallback timeout/cancel | Restore the owned clipboard generation; publish nothing |
| Clipboard changed externally | Preserve the external content; publish nothing |
| Clipboard item has file and text representations | Reject the object, restore, publish nothing |
| Dynamic UTI resolves to a legacy file-list pasteboard type | Reject the object, restore, publish nothing |
| Secure field | Return `secureInput`; never copy or expose text |
| No supported selection | Quietly invalidate/dismiss; never reuse old context |

### 5. Good / Base / Bad Cases

- Good: a WebView exposes selection on an `AXGroup`; pointer hit-test plus
  ancestor traversal resolves it and presents the panel.
- Good: Qt/QML custom text exposes no AX selection semantics; an explicit
  drag enters compatibility copy and publishes only validated text.
- Good: Qt/QML custom text passes second-mouse-down preflight and may use
  compatible copy; an image target is rejected using its pre-open AX path.
- Good: WeChat exposes an empty AX path for both text and images; native I-beam
  permits the text attempt while the image's arrow cursor keeps it strict.
- Base: TextEdit drag selection resolves standard selected text and range.
- Good: double-clicking a Finder or IDE folder is rejected before copy when the
  hit path supplies no positive text-selection evidence.
- Good: double-clicking an IDE tab is rejected before copy when its hit path has
  no text-selection semantics, even if the focused editor retains a selection.
- Bad: every global mouse-up captures whatever text remains highlighted.
- Bad: accepting `.string` before checking whether the same item is a file,
  image, or another typed object.
- Bad: implementing the shortcut with a normal key monitor, which can duplicate
  source-app input or interfere with IME composition.

### 6. Tests Required

- `Scripts/verify-overlay-state.sh` asserts explicit gesture rules, fallback
  success, equal-text detection, multi-type restore, timeout, cancellation,
  concurrent clipboard changes, compatible drag for empty/custom AX paths,
  second-mouse-down multi-click preflight propagation, safe missing-preflight
  fallback, empty-path I-beam/arrow policy, AX hit classification for
  text/file-tree/tab/image/control targets, file-object
  rejection, native private-flavor restore, policy persistence, capture-before-
  policy rejection, source switching, explicit-capture bypass, fail-before-
  clear snapshot limits, and Carbon hot-key ID isolation.
- `swift build --target ClipAll` verifies AppKit/Carbon integration compiles.
- Manual QA must use `/Applications/ClipAll.app`: test TextEdit drag, double
  click, retained-highlight single click, normal typing, registered shortcut,
  one `dragOnly` App, one `disabled` App, and one AX-opaque App where text drag
  and double-click work while double-clicking non-text content sends no copy.

### 7. Wrong vs Correct

#### Wrong

```swift
NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
    captureCurrentSelection()
}
```

#### Correct

```swift
NSEvent.addGlobalMonitorForEvents(
    matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
) { event in
    // Preflight the original second mouse-down target before multi-click UI changes;
    // drag stays compatible and Shift-click stays AX-only.
}
```

#### Wrong: Treat every empty AX path as non-text

```swift
if path.isEmpty { return .textHitRequired }
```

#### Correct: Require native I-beam evidence for an empty path

```swift
return SelectionHitClassifier.multiClickFallbackPolicy(
    in: path,
    hasTextSelectionCursor: matchesNativeIBeam(NSCursor.currentSystem)
)
```

## Good / Base / Bad Cases

- Good: expanding keeps the compact action bar fixed and adds content only below
  it, regardless of whether the initial panel was placed above or below text.
- Base: a new selection context recomputes its screen and placement.
- Bad: deriving every state from `fittingSize.width`, which makes the toolbar jump
  horizontally.
- Bad: observing ordinary `keyDown` events and returning a modified event; this
  can duplicate source-app text input.

## Review Checklist

- No unscoped `WindowGroup` in the menu-bar app.
- No global window-style mutation in `AppDelegate`.
- No fixed light-only surface or saturated accent in feature views.
- No launch of `.build/ClipAll.app`; `.build` is an intermediate bundle only.
- Geometry behavior has numeric assertions, not screenshot-only coverage.
- No `resignKey -> dismiss` observer on the overlay; outside-click and workspace
  activation monitors own dismissal so TextInputUI helper windows cannot close it.
