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
