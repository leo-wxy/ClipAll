# 修复超高选区浮窗贴顶

## Goal

避免 App 返回超高或异常选区矩形时，取词浮窗被边界夹取到屏幕最顶部；浮窗应保持在
用户本次选择操作附近。

## Confirmed Facts

- 初始定位优先使用 `SelectionContext.selectionBounds`，不存在时才使用 `triggerLocation`。
- 当前算法在选区下方放不下时直接尝试上方；上方也放不下时会把窗口夹到屏幕顶部。
- 新选区使用新的 context ID，不会复用上一次选区的窗口锚点。
- 现有验证覆盖普通上下放置和屏幕边界，但未覆盖“完整选区上下都放不下”的场景。

## Requirements

- 普通选区只要上方或下方至少一侧能完整容纳浮窗，必须保持现有 selection-bounds-first
  定位行为。
- 当完整选区矩形上下两侧都无法完整容纳浮窗时，使用当前 context 的
  `triggerLocation` 作为定位锚点，再沿用现有上下放置与屏幕边界夹取规则。
- 浮窗不得越过当前屏幕 `visibleFrame`，不得引入动画、窗口重建或延迟同步。
- 不修改 AX 文字捕获、选区过滤、窗口层级、展开/收缩锚点和公开数据结构。
- 使用现有 `OverlayPlacement` 纯计算入口完成修复，不新增布局服务或抽象层。

## Acceptance Criteria

- [x] 确定性验证证明当前算法会把超高选区对应浮窗夹到屏幕顶部。
- [x] 修复后，同一超高选区使用屏幕底部附近的触发点定位，不再贴顶且完整位于
  `visibleFrame` 内。
- [x] 普通下方放置、顶部附近改为上方放置、展开/收缩保持顶边等既有数值断言继续通过。
- [x] `Scripts/verify-overlay-state.sh`、`swift build --target ClipAll` 和
  `git diff --check` 通过。
- [x] 使用稳定的 `ClipAll Local Development` 身份安装并启动
  `/Applications/ClipAll.app`。
- [x] 用户在真实 App 中验收通过后再 commit 和归档。

## Out of Scope

- 重构 Accessibility 坐标转换或为特定 App 增加规则。
- 增加持久化调试日志、设置项或定位动画。

## Notes

- PRD-only 轻量 bugfix。
