# 跨 App 选区兼容：实施计划

## Success Standard

微信等 AX 不返回选区但支持系统复制的 App，在明确拖选、双击/三击或 Shift-click 后可自动显示现有浮窗；AX 正常 App 不触碰剪贴板；任何失败都不产生旧正文、双倍输入或剪贴板覆盖。

## Step 1 — 触发、设置与安全错误

修改：

- `ClipAll/Infrastructure/Accessibility/PointerSelectionGesture.swift`：保持 `Bool` 结果，只加入 Shift-click 判定。
- `ClipAll/Infrastructure/Accessibility/SelectionMonitor.swift`：传入 Shift 状态，保持单击拒绝、任务取消和最终去重。
- `ClipAll/Infrastructure/Accessibility/SelectionCaptureService.swift`：增加独立 `secureInput` 错误，为后续回退建立安全分组。
- `ClipAll/Infrastructure/Persistence/SettingsStore.swift`：新增默认开启的总开关和排除 Bundle ID 集合。
- `ClipAll/Features/Settings/GeneralSettingsView.swift`：内联兼容取词开关和 App 排除管理。
- `Verification/OverlayStateVerification.swift`：覆盖拖选、双击、Shift-click、普通单击和低阈值移动。

验证：`./Scripts/verify-overlay-state.sh`。本步不接入剪贴板，行为除 Shift-click 外应与现状一致。

## Step 2 — 实现并接入剪贴板回退

新增或修改：

- `ClipAll/Infrastructure/Accessibility/ClipboardSelectionFallback.swift`：快照、清空、轮询、恢复与 `SelectionContext` 构建。
- `ClipAll/Infrastructure/Accessibility/SelectionCaptureService.swift`：改为异步 AX 优先链路，仅对允许的 AX 错误进入回退。
- `ClipAll/Infrastructure/Accessibility/SelectionMonitor.swift`：等待异步捕获并保证旧任务失效。
- `ClipAll/App/AppEnvironment.swift`：注入读取当前设置的闭包。
- `Verification/OverlayStateVerification.swift`、`Scripts/verify-overlay-state.sh`：使用命名 pasteboard 和复制闭包验证事务，不新增验证程序或脚本。

验证矩阵：

| 场景 | 期望 |
|---|---|
| 成功复制 | 返回本次文本并恢复原多类型快照 |
| 复制文本等于旧剪贴板 | 仍以 change count 判定成功，不误报失败 |
| 800ms 超时 | 无上下文，恢复原快照 |
| 任务取消 | 不发布结果，恢复原快照 |
| 外部再次修改 | 不恢复，不覆盖外部新内容 |
| 私有类型不可读取或超过上限 | 修改前失败，剪贴板 change count 不变 |

额外断言：AX 成功时 fallback 调用次数为 0；权限错误和安全输入为 0；关闭、排除或来源切换为 0；其余 AX 失败且策略允许时为 1。

## Step 3 — 文档、全量验证与真实 App 矩阵

修改：

- `README.md`、`Docs/Development.md`：说明 AX 优先、复制回退、剪贴板边界和真实 App 验收方法。
- `.trellis/spec/frontend/quality-guidelines.md`：实现验证后记录新的选区兼容合同。

UI 验收只检查设置可理解性和持久化；不改浮窗布局、图标、插件页或能力路由。

自动验证按顺序执行：

1. `zsh -n Scripts/*.sh`
2. `./Scripts/verify-overlay-state.sh`
3. `./Scripts/verify-all.sh`
4. `swift build --target ClipAll`

安装后仅测试 `/Applications/ClipAll.app`：

| App 类别 | 必测动作 | 记录内容 |
|---|---|---|
| TextEdit | 拖选、双击、Shift-click、普通单击、输入 | AX 成功且剪贴板不变 |
| Safari | 网页文字拖选 | AX 路径、bounds 与浮窗位置 |
| Chrome/VSCodium/Codex | 网页或编辑器拖选 | AX 或回退路径、无双倍输入 |
| WeChat | 消息文字选区 | AX 失败时复制回退、剪贴板恢复 |
| Word/Preview/PDF Expert | 文档/PDF 选区 | 支持路径或确定失败，不复用旧内容 |

## Review And Rollback Gates

| Gate | 阻断条件 | 回滚点 |
|---|---|---|
| Trigger | 单击或普通输入触发捕获 | 仅回滚 Step 1 手势返回值 |
| Clipboard | 任一成功/失败路径可能丢剪贴板 | 不接入捕获链，保留 AX-only 行为 |
| Integration | AX 成功仍修改剪贴板 | 关闭默认开关并回滚 layered routing |
| UI | 设置不能明确说明副作用或排除项不持久 | 保留策略字段，暂不暴露 UI |
| Release | `/Applications` 实测出现双倍输入或来源失焦 | 兼容取词默认改为关闭，AX-only 继续可用 |
