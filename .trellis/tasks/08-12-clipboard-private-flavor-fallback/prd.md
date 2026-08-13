# 修复非 AX App 剪贴板私有类型取词失败

## Goal

当 VSCode 等 App 无法通过 Accessibility 直接提供选区时，ClipAll 仍能在不丢失原剪贴板任何显式类型或数据的前提下完成兼容取词并显示浮窗。

## Background

- 运行日志确认双击与拖选均已进入捕获链，但 VSCode 的 AX 路径失败后，剪贴板回退以 `unsafePasteboard` 终止；Codex 与 Android Studio 可通过 `source=ax` 正常显示。
- 当前剪贴板是一项 Qt 图片，包含 5 个原始类型。`NSPasteboardItem.data(forType:)` 无法读取 `com.trolltech.anymime.IMAGE_PATH` 与 `com.trolltech.anymime.COPY_OR_CUT_FROM_THIS_APPLICATION`，因此现有逐类型 AppKit 快照在清空前失败（`ClipboardSelectionFallback.swift#snapshotPasteboard`）。
- macOS 公开 Pasteboard Manager 已在当前现场验证：上述 5 个原始类型都能读取，并能完整写入临时命名 Pasteboard；两个私有类型分别保留 112 字节和 4 字节。通用剪贴板未在探针中修改。

## Requirements

- R1：生产路径使用 macOS 公开 Pasteboard Manager 读取并恢复原剪贴板的全部显式 flavor；不得丢弃 AppKit 无法解析的私有类型。
- R2：系统自动转换出的 flavor 不重复快照；原始 flavor 的数据和可由调用方设置的 flags 必须保留。
- R3：继续执行现有 16 item、64 type、32 MiB 上限。任何原始 flavor 无法物化、超过上限或恢复失败时保持 fail closed。
- R4：现有 change-count 所有权、超时、取消、第三方并发写入和新复制结果的非文本对象过滤语义保持不变。
- R5：AX 成功路径、手势判定、浮窗布局、按 App 排除、设置和能力执行不在本次修改范围内。
- R6：选中文字及剪贴板正文保持仅在内存中，不写日志或临时文件。

## Acceptance Criteria

- [ ] AC1：原剪贴板包含上述 Qt 图片私有类型时，VSCode 双击或拖选真实文本能够进入剪贴板回退并显示浮窗，不再返回 `unsafePasteboard`。
- [ ] AC2：兼容取词成功、超时和取消后，原剪贴板的显式 item、flavor、字节数据均完整恢复；第三方并发写入仍不被覆盖。
- [ ] AC3：超过快照上限、原始 flavor 无法读取或恢复 API 失败时，在不覆盖用户剪贴板的前提下安静失败。
- [ ] AC4：文件、图片及动态文件对象作为本次复制结果时继续被拒绝；AX 成功时仍不发送 `Command-C`。
- [ ] AC5：自动验证覆盖至少一个 AppKit 无法表示、但 Pasteboard Manager 可完整往返的私有 flavor，并通过 `Scripts/verify-overlay-state.sh`、`Scripts/verify-all.sh` 与 `swift build --target ClipAll`。
- [ ] AC6：当前构建通过 `Scripts/install-local-app.sh` 安装并启动 `/Applications/ClipAll.app`，由用户在 VSCode 与一个 AX 正常 App 中完成真实验收。

## Out Of Scope

- 改变手势过滤、误触策略或 AX 选区解析。
- 丢弃不可识别的剪贴板类型、只保存文本/图片等降级快照。
- 引入 OCR、浏览器扩展、进程注入或 App 专属规则。
- 修改浮窗 UI、动画、路由或插件能力。
