# 跨应用选区捕获兼容实施计划

## Success Standard

POPO 空 AX 正文双击可弹窗，同时 IDE 文件树 / Tab 等已有误触场景继续被拒绝；自动验证、稳定签名安装和用户手测全部完成。

## Ordered Checklist

1. 在 `Verification/OverlayStateVerification.swift` 先补谓词回归：
   - 空路径允许双击回退；
   - 正文路径允许回退；
   - 文件树、Tab、按钮和非空无选区语义路径拒绝回退；
   - 手势策略保持拖选允许、双击仅拒绝已知非文字、Shift-click 禁用。
2. 在 `PointerSelectionGesture.swift` 将双击策略从含糊的 `textHitRequired` 改为 `rejectKnownNonText`。
3. 在 `SelectionCaptureService.swift`：
   - 将现有布尔方法改名为 `allowsClipboardFallback`；
   - 空命中链返回允许，明确非文字与非空无文字语义返回拒绝；
   - 允许时直接复用现有 `ClipboardSelectionFallback`；
   - 移除 120ms 延迟重试和 `[DEBUG-popo-selection]` 临时探针；
   - 正式日志不包含文字、标题或路径内容。
4. 运行定向验证并修正失败：
   ```bash
   Scripts/verify-overlay-state.sh
   ```
5. 运行完整回归与 SwiftPM 主 target 构建：
   ```bash
   Scripts/verify-all.sh
   env CLANG_MODULE_CACHE_PATH="$PWD/.swift-module-cache" \
     SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.swift-module-cache" \
     swift build --target ClipAll --disable-sandbox --build-system native
   ```
   当前 `Package.swift` 没有 XCTest target；按本地构建规范，不为让 `swift test` 成功而新增永真测试 target。
6. 静态检查：
   - `rg '\[DEBUG-popo-selection\]|hitEvidenceSummary|textHitRequired' ClipAll Verification` 无残留；
   - `git diff --check` 通过；
   - diff 只包含本任务文件。
7. 使用稳定本地签名构建、替换并启动真实 App：
   ```bash
   Scripts/install-local-app.sh
   ```
8. 用户手测矩阵：
   - POPO 正文双击：应弹窗；
   - IDE 文件树双击：不弹窗；
   - VSCode 正文双击：应弹窗；
   - VSCode Tab 双击：不弹窗；
   - 普通输入框选中文字：应弹窗；
   - 空白区域普通单击：不弹窗。
9. 只有用户明确确认手测通过后，才进入 Trellis 检查、spec 更新、commit 与归档。

## Risk and Rollback Points

- 风险集中在 `SelectionHitClassifier` 的空路径边界；剪贴板协议不应改动。
- 若定向回归失败，先回滚分类与策略命名，不修改对象类型过滤列表来掩盖问题。
- 若 POPO 仍失败，先读取正式分类 / fallback 错误日志，不继续增加固定延时或 App 白名单。
- 若新增不可接受误触，恢复空路径拒绝即可；无持久化迁移或数据清理。
