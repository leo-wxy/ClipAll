# 浮窗关闭时序与选择误触修复

## Goal

修复两类浮窗交互回归：点击“搜索”等外部能力后浮窗先改变高度再延迟消失；双击文件夹等非文本对象时，ClipAll 误用复制回退取得对象字符串并显示浮窗。

## Requirements

### 已验证事实

- 真实运行日志显示点击“搜索”后 `LaunchServices` 正常打开浏览器，没有崩溃或执行失败。
- `SelectionOverlayStore.execute` 当前对所有能力先设置 `.executing`，导致浮窗增加“正在执行”内容并触发窗口尺寸同步。
- 搜索返回 `.external` 后，Store 又进入 `.message("已在浏览器中打开")`，等待 650ms 才调用 `dismiss()`。
- Coordinator 通过延后一轮的 `objectWillChange` 同步隐藏 panel；单独调用 `store.dismiss()` 并不保证 panel 在同一事件周期立刻 `orderOut`。
- `PointerSelectionGesture` 当前把任何 `clickCount >= 2` 都当成选词动作，且只返回 `Bool`，后续捕获无法区分拖选与双击。
- 双击文件夹现场的 AppKit 日志显示 ClipAll 随后进入通用剪贴板读取轮询，证明误触来自 AX 失败后的 `Command-C` 回退，而不是真实文本选区。
- DevEco 现场日志显示文件夹复制结果为多个 `dyn.*` 类型加 `public.utf8-plain-text`；macOS 将其中的动态 UTI 解析为 `NSFilenamesPboardType`、`text/uri-list` 和 `x-special/gnome-copied-files`，证明只比较外层 UTI 字符串会漏掉文件对象。

### 行为要求

- 外部能力在执行前必须立即把 Store 置为不可见，并同步隐藏 `NSPanel`。
- 外部能力不得进入 `.executing`、`.message` 或其他会改变浮窗高度的阶段。
- 外部副作用在浮窗隐藏后执行；成功后记录最近使用，失败只记录不含选中文字的诊断信息，不重新弹出旧浮窗。
- 普通结果能力和翻译能力继续保留现有执行中、结果与错误 UI。
- 不能按 `CapabilityID.search` 特判；外部呈现行为必须由能力执行合同声明，并提供不影响现有能力的默认值。
- 修复不得引入新的窗口动画、延时隐藏或 hosting root 重建。
- 临时 frame/phase 定位日志使用唯一前缀，根因确认后必须全部删除。

### 选择意图要求

- 拖选、双击/三击、Shift-click 仍然可以触发 AX 读取；AX 能返回真实选中文字时继续显示浮窗。
- 拖选、注册快捷键和菜单手动捕获可以在 AX 失败后进入剪贴板回退；双击/三击只有在鼠标 AX 命中链具备选区属性或字符范围语义时才能回退；Shift-click 保持 AX-only。
- 双击 IDE Tab、按钮或列表项时，即使焦点编辑器仍保留真文字选区，也必须在发送 `Command-C` 前拒绝，不能复制并显示残留选区。
- Electron/VSCode 正文可同时声明选区属性与 `AXShowMenu`；`AXShowMenu` 不能单独否决，必须完整扫描有界祖先链，确认没有 `AXRow`、Tab、Button 或 `AXPress` 等硬控件语义后再允许。
- 双击/三击回退必须先检查复制结果的语义类型；文件树、列表、图片和按钮等对象不能因为附带字符串表示就显示浮窗。
- 剪贴板回退取得的新内容若包含文件 URL、文件列表、promised-file、图片、音视频、PDF、归档、vCard 或字体类型，必须按非文本对象拒绝。
- 动态 UTI 必须解析其 `com.apple.nspboard-type` 别名后再分类，不能硬编码某次运行生成的 `dyn.*` 哈希。
- 普通单击继续不触发任何捕获，不复用旧高亮选区。

## Acceptance Criteria

- [ ] 回归验证在当前代码上能证明：触发外部能力后 Store 仍可见或进入执行阶段。
- [ ] 修复后，调用外部能力的 `execute` 返回时 `store.isVisible == false`，且没有 `.executing`/`.message` 中间状态。
- [ ] Coordinator 收到 `isVisible = false` 时同步 `orderOut`，不等待下一次 panel 尺寸同步。
- [ ] 点击搜索后浏览器仍能正确打开查询 URL，并记录搜索为最近使用。
- [ ] 搜索失败不会重建已经关闭的浮窗，也不会泄露选中文字到日志。
- [ ] 复制、粘贴、翻译、结果面板和“更多”展开行为无回归。
- [ ] 双击/三击原生文本时走 AX；不暴露 AX 选区的正文仍能通过受控复制回退显示浮窗。
- [ ] 双击文件夹、列表项或按钮且 AX 无文本时，即使执行复制回退，也必须拒绝带对象类型的结果且不显示浮窗。
- [ ] 双击 IDE Tab 时不发送复制回退，也不显示焦点编辑器残留选区；双击 Codex/Chromium/VSCode 正文仍可回退取词。
- [ ] Shift-click 非文本对象时不执行剪贴板回退；拖选非 AX 文本仍可使用回退。
- [ ] 快捷键和菜单手动捕获在 AX 失败时仍可使用复制回退。
- [ ] 带文件 URL、文件列表、promised-file、图片或其他已声明对象类型的复制结果被拒绝，并完整恢复原剪贴板。
- [ ] `Scripts/verify-overlay-state.sh`、`Scripts/verify-all.sh` 和 Swift 构建通过。
- [ ] 使用稳定签名安装到 `/Applications/ClipAll.app` 后，用户确认搜索按钮不再产生上移或延迟消失。

## Notes

- 本修复涉及 Domain 执行合同、Store 状态与 AppKit panel 生命周期，按复杂任务补充技术设计和实施计划。
