# 完善 Qt 兼容取词

## Goal

让 Qt/QML 等缺少 AX 文字语义的自定义文本控件通过拖选和双击显示浮窗，同时确保双击
图片等非文字操作不会收到 ClipAll 发送的复制快捷键。

## Confirmed Facts

- Qt/QML 自定义文本控件可能不暴露可用的 AX 文字语义。
- 真实日志确认拖选已进入捕获，但 AX 返回 `noFocusedElement`，现有
  `textHitRequired` 因 `pointerTargetNotTextual` 阻止剪贴板回退。
- 兼容取词全局默认开启；问题不是应用规则过滤。
- 现有剪贴板回退会快照并恢复剪贴板，并在读取文字前拒绝图片、文件等非文字类型。
- 微信实测中，文字与图片双击的 AX 命中链都为空；文字区域使用系统 I-beam 光标，图片
  区域使用箭头光标，可作为空命中链下的正向文字证据。

## Requirements

- 默认拖选是强选择意图：AX 无法提供文字语义时，允许进入兼容剪贴板回退。
- 第二次鼠标按下时预检原始目标；非空自定义文字路径可升级为兼容回退；AX 命中链为空
  时仅系统 I-beam 光标可升级。图片、按钮、箭头光标或缺失按下预检时继续使用严格文字
  门禁。
- 鼠标抬起后的捕获必须使用原始位置，不能改用延迟后的当前鼠标位置。
- 兼容拖选仍须拒绝 AX 已明确识别出的按钮、文件行、Tab 控件、菜单、图片等非文字对象。
- Shift-click 继续禁止剪贴板回退；快捷键和菜单行为不变。
- 剪贴板回退仍只接受非空纯文字，并保留现有非文字类型拒绝、并发写入保护和恢复语义。
- 复用现有应用规则和兼容取词开关，不新增持久化字段、App 白名单或 Qt App 特例。

## Acceptance Criteria

- [x] 拖选使用兼容策略，缺少文字属性的自定义 `AXGroup` 路径可以进入回退。
- [x] 兼容策略仍拒绝 `AXImage`、按钮、文件树行和明确的 `AXTabButton` 路径；
  双击的未知 IDE Tab 路径继续被严格门禁拒绝。
- [x] 双击默认使用 `textHitRequired`；非空文字路径或空路径下的系统 I-beam 可升级为兼容
  策略，图片、箭头光标或缺失按下预检时保持严格策略。
- [x] Shift-click 仍使用 `disabled`，快捷键和菜单仍使用 `enabled`。
- [x] 现有剪贴板文字/图片/文件/超时/取消/并发恢复验证继续通过。
- [x] `Scripts/verify-overlay-state.sh`、`swift build --target ClipAll`、
  `Scripts/verify-all.sh` 和 `git diff --check` 通过。
- [x] 使用稳定的 `ClipAll Local Development` 身份安装并启动
  `/Applications/ClipAll.app`。
- [x] 用户在真实 Qt App 中双击文字可显示浮窗，双击图片不触发“已复制”后再 commit 和归档。

## Out of Scope

- 为单个 Qt App 增加专用适配器或 bundle 白名单。
- 屏幕截图/OCR、Qt 私有 API 注入或其他进程内适配。
- 新增应用规则 UI、修改全局快捷键或 AX 坐标逻辑。

## Notes

- PRD-only 轻量 bugfix。
