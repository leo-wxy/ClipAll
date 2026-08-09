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
- Initial placement is selection-bounds first and pointer fallback second.
- Resizing preserves the edge nearest the selection: a panel below the selection
  preserves `maxY`; a panel above it preserves `minY`.
- Copy success dismisses immediately. New visual animation must not delay the
  store's dismissal or intercept source-app key events.

```swift
let edge = OverlayPlacement.attachmentEdge(for: frame, anchor: anchor)
let resized = OverlayPlacement.resizedFrame(
    from: frame,
    panelSize: newSize,
    visibleFrame: screen.visibleFrame,
    attachmentEdge: edge
)
```

## Good / Base / Bad Cases

- Good: expanding below a selection keeps the panel top edge fixed and does not
  cover the selected text.
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
