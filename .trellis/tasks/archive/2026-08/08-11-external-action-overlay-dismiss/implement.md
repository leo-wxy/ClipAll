# 浮窗关闭与选择误触：实施计划

## Success Standard

点击“搜索”时浮窗原地立即消失，之后浏览器打开；非 AX 正文双击仍能取词，而双击文件夹等带对象类型的内容不显示浮窗。

## Step 1 — 建立红色反馈回路

- 在 `SelectionOverlayCoordinator.swift` 和 `SelectionOverlayStore.swift` 加入 `[DEBUG-overlay-search]` 临时日志，记录点击、phase、`isVisible`、panel frame、同步原因和 `orderOut` 时间。
- 安装稳定签名版本，让用户复现一次并读取统一日志，确认是执行阶段、650ms 消息还是延迟 `orderOut` 导致位移。
- 在 `Verification/OverlayStateVerification.swift` 增加外部能力立即关闭断言，并调整验证编译输入；修复前必须失败。
- 增加手势意图测试：drag/multiClick 允许受控 fallback，Shift-click 只允许 AX；修复前必须失败。
- 增加含 file URL 与纯文本并存的 pasteboard 场景；修复前必须错误地返回文本。
- 增加 DevEco 现场 `dyn.* + public.utf8-plain-text` 文件对象和 Chromium `source metadata + HTML + plain text` 真文字场景。

## Step 2 — 修复执行与窗口合同

- `Capability.swift`：增加带默认值的 `CapabilityExecutionPresentation`。
- `SearchPlugin.swift`：声明 `.external`。
- `SelectionOverlayStore.swift`：外部能力先关闭后执行；删除外部 650ms 提示路径以及因此失效的状态和任务。
- `SelectionOverlayCoordinator.swift`：在可见状态变为 false 时同步隐藏 panel。
- `SelectionOverlayView.swift`：删除不再可达的 `.message` UI 分支；不改按钮按压动画和“更多”旋转动画。

## Step 3 — 修复选择误触合同

- `PointerSelectionGesture.swift`：返回 `PointerSelectionIntent?`，保留现有 4pt 阈值。
- `SelectionMonitor.swift`：向捕获服务传递 disabled/textHitRequired/enabled 三态策略；快捷键/菜单保持 enabled。
- `SelectionCaptureService.swift`：在 AX 失败分支执行策略门控；多击完整扫描鼠标命中链，以选区属性为正证据、以 AXRow/Tab/Button/AXPress 为硬否决；不把 Electron 正文通用的 AXShowMenu 当作否决。
- `ClipboardSelectionFallback.swift`：拒绝文件 URL、文件列表、promised-file 与常见非文本对象类型；动态 UTI 先解析 `com.apple.nspboard-type` 别名；失败路径恢复原剪贴板。
- `Verification/OverlayStateVerification.swift`：覆盖 Codex 文本命中、VSCode AXShowMenu 正文、VSCode 深层 AXRow、IDE 文件树、IDE Tab、文本容器内按钮、Shift-click、drag 与非文本 pasteboard。

## Step 4 — 验证、清理和安装

1. 运行定向 Overlay 验证，确认红转绿。
2. 删除全部 `[DEBUG-overlay-search]` 临时日志并用 `rg` 确认零残留。
3. 运行 `Scripts/verify-overlay-state.sh`、`Scripts/verify-all.sh` 和主程序构建。
4. 运行 `Scripts/install-local-app.sh`，替换并启动 `/Applications/ClipAll.app`。
5. 等待用户点击搜索、双击文本和双击文件夹手动验收；用户确认前不 commit、不归档任务。
