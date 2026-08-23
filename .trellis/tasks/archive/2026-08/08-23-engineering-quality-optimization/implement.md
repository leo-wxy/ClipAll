# 实施计划

## 1. 建立基线

- 记录 `git status --short`，保留用户已有未跟踪任务目录。
- 运行 `zsh -n Scripts/*.sh`、`Scripts/check-version.sh` 和定向 `Scripts/verify-overlay-state.sh`。
- 再次确认 `selectionCapture`、`overlayStore`、`clipAllSurface` 和 `actionButton` 的全仓引用。

## 2. 删除冗余持有与重复规则

- `ClipAll/App/AppEnvironment.swift`：删除 `selectionCapture`、`overlayStore` 属性及赋值，保留局部变量和真实所有者。
- `ClipAll/Infrastructure/Persistence/SettingsStore.swift`：让删除与加载清理路径复用 `normalizedBundleIdentifier`。
- 运行 `Scripts/verify-overlay-state.sh` 和 `swift build --target ClipAll --disable-sandbox --build-system native`。

## 3. 删除 UI 死代码与纯转发层

- `ClipAll/SharedUI/ClipAllTheme.swift`：删除无引用 Surface modifier/API 及专用常量。
- `ClipAll/Features/SelectionOverlay/SelectionOverlayView.swift`：直接使用 `OverlayActionButton`，删除 `actionButton` wrapper。
- 用 `rg` 确认死符号无残留，再运行完整主 App 编译。

## 4. 收束质量入口与规范

- `Scripts/verify-all.sh`：增加全部 zsh 脚本语法检查。
- `Docs/Development.md`：收束到版本检查和聚合验证入口。
- `.trellis/spec/backend/logging-guidelines.md`：写入当前 OSLog 规范与隐私禁止项。
- `.trellis/spec/backend/index.md`、`.trellis/spec/frontend/index.md`：只修正本阶段实际完成文档的状态，不补无关模板。

## 5. 完整验证

```sh
zsh -n Scripts/*.sh
Scripts/check-version.sh
Scripts/verify-overlay-state.sh  # 私有 pasteboard 场景需在非受限沙箱运行
Scripts/verify-all.sh            # 同上
swift build --target ClipAll --disable-sandbox --build-system native
git diff --check
```

- 若私有 pasteboard 验证只在受限沙箱失败，使用同一未修改脚本在沙箱外复核；只有沙箱外也失败才作为产品回归处理。
- 检查最终 diff，确保没有插件源码、第三方依赖、target 或用户可见行为变化。
- 通过 `trellis-check` 完成独立复核；未通过前不提交、不归档。
