# 低打扰取词浮窗实施计划

## Step 1 — 自动捕获安静期

1. 在 `SelectionMonitor` 将鼠标自动捕获默认等待从 `45ms` 调整为 `120ms`。
2. 新鼠标按下时取消尚未执行的捕获任务，并将 `CancellationError` 作为静默正常路径。
3. 在 `OverlayStateVerification` 增加等待期、取消和正常到期验证；保留零延迟测试入口。

## Step 2 — 收束收缩态

1. 将 `SelectionOverlayView` 的统一宽度从 `324pt` 调整为 `280pt`。
2. 操作栏渲染全部固定能力的前两个；保留复制和“更多”，移除直显粘贴。
3. 在“更多”顶部复用现有按钮样式展示粘贴及剩余固定能力，再显示插件发现内容。
4. 允许长名称在紧凑按钮内收紧或省略，并保留完整 hover 与辅助功能名称。
5. 同步 `CapabilitiesSettingsView` 的预览和说明，明确固定顺序前两项常驻。

## Step 3 — 验证与本地安装

1. 运行 `Scripts/verify-overlay-state.sh`。
2. 运行 `swift build --target ClipAll` 与 `git diff --check`。
3. 检查 `ClipAll Local Development` 稳定身份以及安装前签名 requirement。
4. 运行 `Scripts/install-local-app.sh`，安装后复核主 App 与 Runner 签名并确认进程启动。
5. 用户验证连续操作、正常取词、操作可达性和展开稳定性；确认前不 commit 或归档。

## Risk Checks

- 不让 mouseDown 取消菜单或快捷键已经开始的主动捕获。
- “更多”中的溢出固定能力不得与插件发现列表重复。
- 四个固定能力及较长名称不得造成 `280pt` 内容溢出。
- 不修改 recommendation、结果卡片、插件路由或剪贴板状态机。
