# 完善 Qt 兼容取词

## Goal

让 Qt/QML 等缺少 AX 文字语义的自定义文本控件通过拖选和双击显示浮窗；复制结果为
图片、文件等非文字时不显示浮窗，并在来源 App 完成重复写入后安全清理剪贴板。

## Confirmed Facts

- Qt/QML 自定义文本控件可能不暴露可用的 AX 文字语义。
- 真实日志确认拖选已进入捕获，但 AX 返回 `noFocusedElement`，现有
  `textHitRequired` 因 `pointerTargetNotTextual` 阻止剪贴板回退。
- 兼容取词全局默认开启；问题不是应用规则过滤。
- 剪贴板类型只能在发送复制后读取；PoPo 的文字和图片在复制前均为 `roles=none` 且使用
  箭头光标，无法用通用 AX 或光标信号提前区分。
- 微信实测中，文字与图片双击的 AX 命中链都为空；文字区域使用系统 I-beam 光标，图片
  区域使用箭头光标，可作为空命中链下的正向文字证据。
- PoPo 实测中，双击文字和图片在复制前均为 `roles=none`，并使用完全相同的系统箭头
  光标；App root 同点命中及窗口子树 AX 激活后结果仍为空，无法在发送复制快捷键前区分。
- PoPo 拖选仍可通过兼容回退取得文字，不会依赖双击目标分类。
- 微信图片复制实测会在约 50ms 内依次写入临时纯文字、`public.file-url`，最后补齐 Qt
  image 与 TIFF；这些 changeCount 都属于同一次 `⌘C` 事务。

## Requirements

- 默认拖选是强选择意图：AX 无法提供文字语义时，允许进入兼容剪贴板回退。
- 第二次鼠标按下时预检原始目标；非空自定义文字路径或空 AX 命中链使用兼容回退。
  AX 已明确识别为图片、按钮、文件行、Tab 等对象时仍在复制前拒绝；缺失按下预检时
  保持严格文字门禁。
- 鼠标抬起后的捕获必须使用原始位置，不能改用延迟后的当前鼠标位置。
- 兼容拖选仍须拒绝 AX 已明确识别出的按钮、文件行、Tab 控件、菜单、图片等非文字对象。
- Shift-click 继续禁止剪贴板回退；快捷键和菜单行为不变。
- 剪贴板回退在首次变化后统一等待 120ms 安静窗口；窗口内任何 changeCount 变化都重新
  计时，安静后才按最终类型发布非空文字或拒绝非文字对象。
- 非文字结果稳定后：原剪贴板含文字则恢复原文字，原剪贴板也是非文字则清空；外部
  写入若发生在最终分类或恢复/清理阶段，必须由精确 changeCount 门禁保留。
- 复用现有应用规则和兼容取词开关，不新增持久化字段、App 白名单或 Qt App 特例。

## Acceptance Criteria

- [x] 拖选使用兼容策略，缺少文字属性的自定义 `AXGroup` 路径可以进入回退。
- [x] 兼容策略仍拒绝 `AXImage`、按钮、文件树行和明确的 `AXTabButton` 路径；
  双击的未知 IDE Tab 路径继续被严格门禁拒绝。
- [x] 双击默认使用 `textHitRequired`；非空兼容路径和空 AX 路径可升级为兼容策略，明确
  图片/控件路径或缺失按下预检时保持严格策略。
- [x] Shift-click 仍使用 `disabled`，快捷键和菜单仍使用 `enabled`。
- [x] 剪贴板文字/图片/文件/超时/取消/并发恢复验证继续通过，并覆盖临时文字 → file URL
  → Qt 图片的分阶段写入清理。
- [x] `Scripts/verify-overlay-state.sh`、`swift build --target ClipAll`、
  `Scripts/verify-all.sh` 和 `git diff --check` 通过。
- [x] 使用稳定的 `ClipAll Local Development` 身份安装并启动
  `/Applications/ClipAll.app`。
- [x] 用户确认兼容模式允许来源 App 短暂执行复制；非文字结果稳定后必须清理，第三方 App
  自身的复制提示无法由 ClipAll 阻止。

## Out of Scope

- 为单个 Qt App 增加专用适配器或 bundle 白名单。
- 屏幕截图/OCR、Qt 私有 API 注入或其他进程内适配。
- 新增应用规则 UI、修改全局快捷键或 AX 坐标逻辑。

## Notes

- 根因修复位于共享剪贴板回退事务，不包含 App 特判。
