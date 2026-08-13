# 实施计划

## Step 1 — 策略模型与持久化

修改：

- `ClipAll/Infrastructure/Accessibility/PointerSelectionGesture.swift`
  - 增加三态 `SelectionAutomaticDisplayPolicy` 及纯策略判断。
- `ClipAll/Infrastructure/Persistence/SettingsStore.swift`
  - 增加拖选、多击全局开关和按 Bundle ID 的显示策略字典。
  - 暴露应用规则 ID 合集、查询、设置与删除方法。
  - 复用现有 fallback 排除集合，不做破坏性迁移。
- `Verification/OverlayStateVerification.swift`
  - 先增加默认值、策略矩阵、重启持久化、旧排除兼容与删除规则验证。

定向验证：

```bash
Scripts/verify-overlay-state.sh
```

## Step 2 — 捕获前门禁

修改：

- `ClipAll/Infrastructure/Accessibility/SelectionMonitor.swift`
  - 注入一个鼠标意图策略闭包。
  - 在 pointer capture 调度前按当前前台 Bundle ID 拒绝禁用规则。
  - 拒绝时不调用 AX 或剪贴板，不影响 hotkey/manual。
- `ClipAll/App/AppEnvironment.swift`
  - 将 `SettingsStore` 的实时策略注入 monitor。
- `Verification/OverlayStateVerification.swift`
  - 使用最小 fake 断言禁用策略不触发捕获，快捷路径语义保持。

定向验证：

```bash
Scripts/verify-overlay-state.sh
```

## Step 3 — 设置页重组

新增或修改：

- `ClipAll/Features/Settings/SelectionSettingsView.swift`
  - 自动显示、应用规则、固定过滤、兼容取词四个卡片。
  - 复用系统 App 选择器和现有主题。
- `ClipAll/Features/Settings/GeneralSettingsView.swift`
  - 只保留快捷键、应用入口与权限。
- `ClipAll/Features/Settings/SettingsRootView.swift`
  - 增加“取词”侧栏并设为默认页。

UI 不增加动画、自定义控件库、独立 view model 或一次性应用选择器抽象。

## Step 4 — 自动验证与检查

```bash
Scripts/verify-overlay-state.sh
Scripts/verify-all.sh
env CLANG_MODULE_CACHE_PATH="$PWD/.swift-module-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.swift-module-cache" \
  swift build --target ClipAll --disable-sandbox --build-system native
```

检查：

- `git diff --check`。
- 日志与源码无选中文字、剪贴板正文或临时诊断。
- 旧 Qt 私有 flavor 回归继续通过。

## Step 5 — 安装与手动验收

```bash
Scripts/install-local-app.sh
```

用户在 `/Applications/ClipAll.app` 验收：

1. 默认全部开启，行为与当前版本一致。
2. 全局关闭多击：VSCode/Codex 双击不弹，拖选可弹。
3. App 设为“仅拖选”：该 App 双击不弹、拖选可弹。
4. App 设为“永不自动显示”：鼠标选择不弹，快捷键仍可主动显示。
5. 文件树、Tab、按钮、安全输入与图片对象继续不误触。
6. 设置页重启后保持，删除 App 规则后恢复全局。

## Finish Gate

- 用户明确测试通过前，不 commit、不归档、不声明完成。
- 测试通过后使用 `trellis-update-spec` 更新选择策略合同，再按仓库规范提交。
- 旧 `08-12-clipboard-private-flavor-fallback` 的修改仍单独核对归属，不把两个 Trellis 任务错误归档为一个。
