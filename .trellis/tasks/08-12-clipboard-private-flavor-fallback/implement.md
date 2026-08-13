# 实施计划

## Step 1 — 建立回归

- 修改 `Verification/OverlayStateVerification.swift`。
- 使用临时命名 Pasteboard 和公开 Pasteboard Manager 写入一个 AppKit 无法表示的 Qt 私有 flavor。
- 断言兼容取词取得本次文本，并按类型和字节恢复原 flavor。
- 保留现有多格式恢复、同文本、超时、取消、并发写入、上限和非文本对象验证。

## Step 2 — 替换生产快照与恢复

- 修改 `ClipAll/Infrastructure/Accessibility/ClipboardSelectionFallback.swift`。
- 对实际 `NSPasteboard` 使用 `PasteboardCreate`、`PasteboardSynchronize`、`PasteboardGetItemCount`、`PasteboardCopyItemFlavors`、`PasteboardCopyItemFlavorData`、`PasteboardClear` 与 `PasteboardPutItemFlavor`。
- 过滤系统转换 flavor，保留原始顺序、数据和可恢复 flags。
- 测试 fake 保持现有 AppKit 内存实现，不改捕获状态机或错误枚举。

## Step 3 — 自动验证

按顺序运行：

```bash
Scripts/verify-overlay-state.sh
Scripts/verify-all.sh
swift build --target ClipAll
```

静态检查产品代码和日志中不存在剪贴板正文、类型列表或临时探针。

## Step 4 — 安装与真实验收

运行：

```bash
Scripts/install-local-app.sh
```

用户验收：

1. 保留能够复现问题的 Qt 图片剪贴板，VSCode 双击和拖选真实文本均显示浮窗。
2. 复制回退后原图片仍可正常粘贴。
3. Codex 或 Android Studio 的 AX 路径继续正常显示。
4. VSCode 文件树、Tab 等已知非文本目标继续不误触。

## Finish Gate

- 用户明确测试通过前，不 commit、不归档、不声明完成。
- 测试通过后更新 `.trellis/spec/backend/quality-guidelines.md` 的剪贴板快照合同，再按仓库 commit 规范提交。

## Rollback Point

若自动验证或真实验收出现任何剪贴板丢失、第三方写入被覆盖或对象误判，回滚 `ClipboardSelectionFallback.swift` 与对应验证改动，保持当前已发布行为。
