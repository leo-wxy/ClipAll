# SwiftUI Component Guidelines

## Scope

ClipAll is a native macOS SwiftUI application. Feature views live under
`ClipAll/Features`, while reusable visual primitives live in
`ClipAll/SharedUI/ClipAllTheme.swift`.

## Window And Navigation Structure

- Use native `NavigationSplitView` and sidebar `List(selection:)` for settings
  and browsing windows.
- Keep `Settings` and singleton `Window(id:)` scenes. Do not add an unscoped
  `WindowGroup` to the menu-bar accessory app; it creates restorable duplicate
  windows.
- Do not globally rewrite every `NSWindow` from `AppDelegate`. Window chrome is
  owned by the corresponding SwiftUI scene.
- A menu action that opens a window must activate the accessory app before the
  open action and again on the next main-queue turn.

```swift
NSApplication.shared.activate(ignoringOtherApps: true)
openSettings()
DispatchQueue.main.async {
    NSApplication.shared.activate(ignoringOtherApps: true)
}
```

## Shared Visual Primitives

Use semantic values from `ClipAllTheme`; do not introduce feature-local orange,
card shadow, selection fill, or common spacing constants.

```swift
ClipAllSectionCard("辅助功能权限", subtitle: "只用于读取当前选区。") {
    content
}

ClipAllIconBadge(
    symbolName: descriptor.symbolName,
    size: ClipAllTheme.Size.iconSmall,
    tone: isSelected ? .accent : .neutral
)
```

- `clipAllSurface()` is for top-level cards.
- `clipAllInset()` is for nested fields and result blocks.
- `ClipAllHoverRow` gives non-selectable rows a pointer affordance.
- `ClipAllSelectableRowStyle` combines hover, pressed, selected fill, and a
  leading accent marker. Selection must not rely on color alone.
- Colors must use semantic `NSColor`-backed tokens so light and dark appearances
  update together.

## State And Accessibility

- Use native switches for persistent boolean preferences.
- Async controls are disabled while their operation is pending and show progress
  when the wait is user-visible.
- Selected rows add `.isSelected`; icon-only state adds an accessibility label.
- Keep text labels for success, failure, unavailable, and disabled states.

## Common Mistakes

- Do not mix hand-written `opacity`, radius, and icon badge values with shared
  tokens for the same semantic role.
- Do not make an accessory app's ordinary window borderless or globally movable
  by its background.
- Do not add a second app launch path for previews or local testing. Visual QA is
  performed against `/Applications/ClipAll.app` only.
