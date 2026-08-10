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
- `PointerSelectionGesture.end(at:clickCount:) -> Bool` returns whether the
  gesture is an explicit selection action and always resets its state.
- `SelectionCapturing.captureCurrentSelection(triggerLocation:)` is the single
  capture entry used by pointer, registered hotkey, and menu commands.

### 3. Contracts

- Pointer auto-capture runs only after a drag at least four points or a mouse-up
  with `clickCount >= 2`. A plain click never reads a retained old selection.
- Keyboard selection is explicit: the Carbon-registered global shortcut may
  capture, but ordinary `NSEvent.keyDown` must never be monitored or replayed.
- Resolve AX candidates in this order: system-wide focus, frontmost application
  focus, then element-at-pointer. For each candidate, inspect a bounded ancestor
  chain for standard selected text/range and Text Marker selection.
- Secure text fields fail closed. Selected text is never written to diagnostics;
  logs may contain only trigger type, AX role, error type, and bounds presence.

### 4. Validation & Error Matrix

| Condition | Required result |
|---|---|
| Single click with retained highlight | No capture and no overlay |
| Drag below four points | No capture |
| Drag at least four points | Capture after the short selection-settle delay |
| Double/triple click | Capture after mouse-up |
| Registered hotkey | Capture without pointer-gesture state |
| Missing system-wide focus | Try frontmost-app focus, then pointer hit-test |
| Text Marker selection only | Resolve text locally; bounds may fall back to pointer |
| Secure field | Return `unsupported` and never expose text |
| No supported selection | Quietly invalidate/dismiss; never reuse old context |

### 5. Good / Base / Bad Cases

- Good: a WebView exposes selection on an `AXGroup`; pointer hit-test plus
  ancestor traversal resolves it and presents the panel.
- Base: TextEdit drag selection resolves standard selected text and range.
- Bad: every global mouse-up captures whatever text remains highlighted.
- Bad: implementing the shortcut with a normal key monitor, which can duplicate
  source-app input or interfere with IME composition.

### 6. Tests Required

- `Scripts/verify-overlay-state.sh` asserts single-click rejection, drag
  threshold behavior, double-click acceptance, and sub-threshold movement.
- `swift build --target ClipAll` verifies AppKit/Carbon integration compiles.
- Manual QA must use `/Applications/ClipAll.app`: test TextEdit drag, double
  click, retained-highlight single click, normal typing, registered shortcut,
  and at least one custom/WebView control.

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
    // Feed a bounded gesture state machine; capture only after drag or multi-click.
}
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
