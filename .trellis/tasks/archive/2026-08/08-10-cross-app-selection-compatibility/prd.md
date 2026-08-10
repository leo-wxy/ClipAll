# 跨 App 选区兼容

## Goal

让 ClipAll 在原生 AppKit、WebKit、Chromium/Electron、富文档和常见自绘控件中尽可能稳定地读取用户刚完成的文字选区；不因兼容性回退而监听普通按键、读取安全输入框、静默覆盖剪贴板或复用旧选区。

## Background

- 当前 `SelectionCaptureService` 已依次尝试 system-wide focus、前台 App focus、鼠标位置命中，并沿有限祖先链读取标准 selected text/range 和 Text Marker。
- 该链路已覆盖标准文本控件及部分 WebView/自绘控件，但目标 App 完全不暴露 Accessibility 选区时，AX 层无法凭空取得文字。
- 当前 `PasteService` 已使用 CGEvent 发送显式粘贴快捷键；仓库没有模拟复制、读取剪贴板或恢复剪贴板的捕获回退。
- README 已明确跨 App 取词依赖目标 App 的 Accessibility 支持，无法承诺所有 App 都返回文字或精确 bounds。
- 本机可用于兼容验收的代表应用包括 TextEdit、Safari、Google Chrome、VSCodium、WeChat、Preview、PDF Expert 和 Microsoft Word。

## Reference Research

### OneClip

- 仓库 README 明确说明 `src/` 只是早期版本，当前正式版是功能更完整的商业软件；公开历史中 PopClip 只出现在 README，公开 Swift 源码没有 `AXSelectedText`、Text Marker 或划词菜单实现，因此无法直接复用其实现代码：[OneClip README](https://github.com/One-Clip/OneClip#readme)。
- 公开源码中的 `AccessibilityPermissionManager` 只负责 `AXIsProcessTrusted` 权限检查；全局鼠标/键盘监控用于用户活跃状态、快捷键和窗口关闭，不包含读取文字选区的兼容链路：[AccessibilityPermissionManager.swift](https://github.com/One-Clip/OneClip/blob/main/src/OneClip/AccessibilityPermissionManager.swift)。
- 正式版发布记录证明划词功能以 AX 为核心并持续处理兼容问题：1.5.7 首次加入 PopClip 选中菜单，1.5.8 改进多个问题，1.6.2 修复“AX 强转问题”，2.0.2 再次改进划词快捷菜单逻辑：[OneClip Releases](https://gitee.com/oneclip/OneClip/releases)。
- 发布记录没有公开 macOS Service、模拟 `⌘C` 或剪贴板恢复作为划词回退的证据；截图/OCR 被作为独立功能发布，不能据此推断它会自动兜底文字选区。
- 可吸收的工程结论：AX 返回值必须先验证 attribute 支持、`AXError`、CF 类型和可选值，禁止强制转换；捕获链应有有限遍历、超时/取消和确定失败状态，并通过真实 App 矩阵验证。OneClip 只能证明“AX 兼容层需要持续加固”，不能解决“目标 App 完全不暴露选区”这一系统边界。

### Selecto

- 捕获顺序是标准 AX → Chrome 专用 AppleScript `window.getSelection()` → 可选“强制选词”；强制选词默认关闭，并支持按 Bundle ID 排除应用：[SelectionMonitor.swift](https://github.com/echosoar/selecto/blob/main/Selecto/Selecto/SelectionMonitor.swift)、[AppPreferences.swift](https://github.com/echosoar/selecto/blob/main/Selecto/Selecto/Managers/AppPreferences.swift)。
- 强制选词用 AppleScript 备份剪贴板 record、发送 `⌘C`、固定等待 50ms、读取文本后恢复；若复制前后文本相同则判失败。该实现简单，但对“选中文字恰好等于原剪贴板”、慢应用、私有/惰性 pasteboard 类型和并发用户复制处理不足。
- Chrome AppleScript 依赖应用专属 Bundle ID 和浏览器允许 Apple Events JavaScript，不适合作为 ClipAll 的通用兼容层。
- 源码使用多个 AX `as!` 强制转换，存在目标 App 返回异常 CF 类型时崩溃的风险；ClipAll 只吸收分层思想，不复制该转换方式。Selecto 使用 MIT 许可证。

### TextGO

- 捕获顺序是原生 AX → Chromium/Electron AX 激活重试 → 剪贴板回退：[macOS platform](https://github.com/C5H12O5/TextGO/blob/main/src-tauri/src/platform/macos.rs)、[selection command](https://github.com/C5H12O5/TextGO/blob/main/src-tauri/src/commands/selection.rs)。
- 原生 AX 失败时，它会对前台进程 best-effort 设置 `AXEnhancedUserInterface=true` 和 `AXManualAccessibility=true`，缓存 PID 5 秒后重试焦点元素；这是值得在 Chromium/Electron 兼容层做受控实验的策略，但属于目标进程行为开关，不能无条件写入所有 App。
- 剪贴板回退默认开启：备份 text/RTF/HTML/image/files 五类内容，清空剪贴板，发送复制键，每 5ms 轮询，最长等待从 1000ms 自适应下降到 200ms，再恢复原内容：[clipboard command](https://github.com/C5H12O5/TextGO/blob/main/src-tauri/src/commands/clipboard.rs)。
- 它额外监测用户在回退期间主动按复制键；发生竞争时跳过恢复，并用短时选区缓存补偿“恢复抢先覆盖用户复制”的竞态。该机制比 Selecto 完整，但仍无法保存任意私有 pasteboard 类型。
- 触发层使用 I-beam 检查、8pt 拖拽阈值、双击、Shift-click 和可选长按；鼠标选区会在 AX 失败后自动进入复制回退，而不是仅限全局快捷键：[mouse handler](https://github.com/C5H12O5/TextGO/blob/main/src-tauri/src/handlers/mouse.rs)。
- TextGO 使用 GPL-3.0，ClipAll 不复制其代码，只独立实现公开行为与状态机思想。

### Comparative Conclusion

- 三个同类产品都以 AX 为第一路径；Selecto 与 TextGO 都确认“模拟复制 + 剪贴板恢复”是实际采用的跨 App 兜底，不只是理论方案。
- TextGO 的 Chromium/Electron AX 激活、轮询等待、用户复制竞态保护和 App/网站阻止名单最有参考价值；Selecto 的默认关闭与按 App 排除适合作为风险控制参考。
- 没有仓库证明 macOS Service 能覆盖微信等自绘控件，因此 Service 可作为额外显式入口，但不应替代复制回退成为主要兼容方案。

## Requirements

### R1. Layered Capture

- Level 1 保持纯 AX 快速路径：标准 selected text/range、Text Marker、focused element、pointer hit-test 与有限祖先遍历。
- Level 2 允许针对已确认的 AX 树差异增加通用属性/参数化属性策略，不按 Bundle ID 写一次性文本抓取逻辑。
- Level 3 在 AX 失败后允许进入复制回退，但前提必须是本次输入已经被判定为拖选、双击/三击、Shift-click、注册快捷键或菜单命令；普通单击不得进入任何捕获路径。
- 每次成功捕获都创建新的 `SelectionContext`；任一回退失败都不得复用历史正文。

### R2. Trigger And Privacy Boundary

- 指针路径只接受达到既有 4pt 阈值的拖选、双击/三击和 Shift-click；保留旧高亮后的普通单击、滚动、窗口拖动和普通输入不得触发。
- 注册的全局快捷键和菜单命令属于明确取词动作；普通 `keyDown` 事件仍不得监听、修改或重放。
- 复制回退默认开启，只在 AX 失败后运行；设置中必须提供总开关和按 Bundle ID 管理的 App 排除名单。
- `AXSecureTextField`、密码框和无法确认安全边界的控件必须返回独立的安全失败，不得继续复制回退。
- 日志不得包含选中文字、剪贴板正文或输入控件值。

### R3. Clipboard Transaction

- 回退开始前固定来源 App 身份并生成一次捕获代次；来源 App 变化、任务取消或新捕获到来时，本次结果立即失效。
- 在修改系统剪贴板前备份有界且可完整恢复的 pasteboard items；快照无法安全建立时终止回退，不得先清空剪贴板。
- 安全快照建立后依次清空剪贴板、发送一次合成 `⌘C`、异步轮询新 change count 与非空文本，整个等待必须有明确上限且不得阻塞主线程。
- 成功、超时和取消都必须尝试恢复原剪贴板；若检测到用户或其他 App 已再次修改剪贴板，则放弃恢复，避免覆盖用户的新内容。
- 回退只接受本次清空以后产生的文本，不得把回退前的剪贴板内容或历史选区误当成本次结果。

### R4. Settings And Compatibility Matrix

- “兼容取词”开关默认开启，设置文案必须明确说明仅在 AX 失败时临时模拟复制并恢复剪贴板。
- 排除名单支持从 macOS App 包解析 Bundle ID、显示 App 名称并移除条目；ClipAll 自身和无法识别 Bundle ID 的目标不得加入。

- Native：TextEdit。
- WebKit：Safari。
- Chromium/Electron：Google Chrome、VSCodium 或 Codex。
- Custom：WeChat。
- Document/PDF：Microsoft Word、Preview 或 PDF Expert。
- 每类至少记录触发动作、AX 自动路径、复制回退路径、bounds 可用性、剪贴板恢复和失败原因。

### R5. Runtime Behavior

- 设置页必须能看出兼容回退是否启用以及哪些 App 已被排除；自动捕获失败保持安静，不弹错误窗口。
- 兼容回退不得造成双倍输入、来源 App 失焦、重复浮窗或旧选区重新出现。
- 自动路径与兼容路径最终复用同一路由、浮窗和执行状态机。

## Out Of Scope

- 屏幕录制权限与 Vision OCR。
- 注入目标进程、私有插件、浏览器扩展或 App 专属脚本。
- 绕过安全输入框、DRM 内容或目标 App 明确拒绝的 Accessibility 边界。
- 对所有 macOS App 作绝对兼容承诺。

## Key Decisions

- 采用 AX 优先、复制回退第二的分层链路，不把 macOS Service 作为主要兼容机制。
- 复制回退只由已经确认的选词手势、注册快捷键或菜单命令触发，默认开启并支持 App 排除。
- 回退以剪贴板事务实现，不监控或改写普通键盘事件；安全输入和无法建立安全剪贴板快照时 fail closed。
- Chromium/Electron AX 行为开关、App 专属脚本、浏览器扩展和 OCR 不进入本阶段；先用真实 App 矩阵判断后续价值。
- TextGO 仅用于理解公开行为与状态机，ClipAll 不复制其 GPL-3.0 代码。

## Acceptance Criteria

- [ ] AC1：TextEdit、Safari 和至少一个 Chromium/Electron App 的拖选可通过 AX 自动显示浮窗。
- [ ] AC2：WeChat 中 AX 可访问的文字选区直接显示；AX 不提供选区但系统复制可用时，确认的选词手势自动进入复制回退并显示同一浮窗。
- [ ] AC3：普通单击、滚动、窗口拖动和普通键盘输入不触发旧选区或重复字符。
- [ ] AC4：AX 成功时剪贴板完全不变；复制回退成功、超时或取消后恢复原内容，检测到外部新内容时不覆盖它。
- [ ] AC5：关闭兼容取词或命中 App 排除名单时只运行 AX；设置重启后保持开关和名单。
- [ ] AC6：安全输入框始终不捕获且不进入复制回退，日志和持久化均不包含正文。
- [ ] AC7：代表 App 矩阵完成真实 `/Applications/ClipAll.app` 验收，并有自动测试覆盖触发策略、AX/回退选择、超时、取消、剪贴板竞争和旧上下文失效。
