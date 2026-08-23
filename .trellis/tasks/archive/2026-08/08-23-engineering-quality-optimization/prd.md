# 非插件代码精简与工程质量优化

## Goal

在不改变 ClipAll 用户可见行为的前提下，删除非插件源码中已经确认的冗余持有、重复规则、死代码和无行为中间层，同时让现有验证入口与项目规范保持一致。

## Background

- `ClipAll/App/AppEnvironment.swift:21-24,84-120` 同时持有 `selectionCapture`、`selectionMonitor`、`overlayStore` 和 `overlayCoordinator`；代码检索确认 `selectionCapture` 已由 `SelectionMonitor` 强持有、`overlayStore` 已由 `SelectionOverlayCoordinator` 强持有，前两项在 `AppEnvironment` 中没有其他调用。
- `ClipAll/Infrastructure/Persistence/SettingsStore.swift:207-267,352-389` 已有统一 Bundle ID 归一化函数，但删除应用规则和持久化数据清理仍重复实现 trim、空值和主 App 排除规则。
- `ClipAll/SharedUI/ClipAllTheme.swift:77-104,194-234` 中 `ClipAllSurfaceModifier`、`clipAllSurface` 及其专用阴影/圆角常量没有生产调用方。
- `ClipAll/Features/SelectionOverlay/SelectionOverlayView.swift:63-90,342-358` 的 `actionButton` 只逐字段转发到同文件 `OverlayActionButton`，没有默认值或附加行为。
- `.trellis/spec/backend/logging-guidelines.md` 仍是占位文档；当前代码已经统一使用 `OSLog.Logger`，且没有发现记录选中文字、剪贴板正文或 secret 的生产日志。
- `.trellis/spec/backend/local-build-and-release.md` 要求检查全部 shell 脚本语法；当前 CI 调用 `Scripts/verify-all.sh`，但该聚合入口还没有执行 `zsh -n Scripts/*.sh`。
- 只读审计未发现现有架构边界违规，也没有发现需要拆分模块、大型 Store 或 SwiftUI View 的证据。

## Requirements

- R1：删除 `AppEnvironment` 对 `selectionCapture` 和 `overlayStore` 的冗余属性持有，保留现有局部构造和真实所有者，生命周期行为不变。
- R2：让应用规则的删除与持久化清理复用现有 `normalizedBundleIdentifier`，不得新增第二个归一化抽象或改变正常 Bundle ID 的存储格式。
- R3：删除确认无调用的 `ClipAllSurfaceModifier`、`clipAllSurface` 及只服务于它们的主题常量；保留仍被使用的 `ClipAllTheme.surface`、`clipAllInset` 和共享设置组件。
- R4：让操作栏直接构造 `OverlayActionButton` 并删除纯转发 `actionButton`，不得改变按钮顺序、状态、点击行为、可访问性或布局修饰。
- R5：在现有 `verify-all.sh` 中增加 shell 语法门禁，使 CI 和 Release 自动继承该检查；不得在 workflow 中重复维护同一命令。
- R6：补齐精简的日志规范，固化 `OSLog.Logger`、级别、稳定元数据、隐私标记和禁止记录内容；不得新增日志封装或第三方依赖。
- R7：开发文档只保留聚合验证入口，避免要求开发者重复执行已被 `verify-all.sh` 包含的单项脚本。
- R8：所有修改必须优先删除或复用现有实现，不为未来扩展增加新协议、helper、缓存、target 或框架。

## Out of Scope

- 外置插件 Manifest、Runner、配置 API、安装事务、开发模板及插件专用构建优化。
- `runnerClient` 和翻译插件配置别名，即使存在精简空间，也因插件边界暂不处理。
- 新增架构扫描器；当前没有实际违规，待出现真实边界回归后再评估。
- 拆分 `SettingsStore`、`SelectionCaptureService`、`SelectionMonitor`、SwiftUI View 或 SwiftPM target。
- 缓存“更多插件”派生数据、调整插件 UI 或优化未经测量的性能路径。
- Developer ID、公证、自动更新、公共插件市场安全模型及第三方 lint。

## Acceptance Criteria

- [x] `AppEnvironment` 不再声明或赋值 `selectionCapture`、`overlayStore`，取词监听和浮窗协调仍由原有真实所有者保持存活。
- [x] 应用规则的添加、设置、删除和加载清理共享同一 Bundle ID 归一化规则；现有规则持久化验证通过。
- [x] 生产源码与现行规范中不再引用 `clipAllSurface`、`ClipAllSurfaceModifier` 和仅供其使用的主题常量；当前任务与历史归档可以保留删除背景。
- [x] `SelectionOverlayView` 不再包含纯转发 `actionButton`；复制、粘贴和固定能力仍直接使用同一个 `OverlayActionButton`。
- [x] `Scripts/verify-all.sh` 会先验证全部 `Scripts/*.sh` 的 zsh 语法，CI/Release 无需增加重复步骤。
- [x] 日志规范与当前 `OSLog.Logger` 使用方式一致，并明确禁止选中文字、剪贴板正文、翻译正文、配置值、API key 和 Keychain secret。
- [x] `Docs/Development.md` 的自动验证入口收束到 `check-version.sh` 和 `verify-all.sh`，不重复列出其内部脚本。
- [x] `zsh -n Scripts/*.sh`、`Scripts/check-version.sh`、`Scripts/verify-overlay-state.sh`、`Scripts/verify-all.sh`、`swift build --target ClipAll --disable-sandbox --build-system native` 和 `git diff --check` 通过。
- [x] 没有新增依赖、target、通用 lint 框架或用户可见功能变化。

## Risks and Deferred Items

- 删除冗余持有前必须再次确认 `SelectionMonitor` 与 `SelectionOverlayCoordinator` 的强引用关系；这是生命周期正确性的唯一关键风险。
- 受限沙箱中的私有 pasteboard 验证会在 `PasteboardCreate` 处失败；同一未修改脚本在沙箱外通过。这是验证运行边界，不是产品回归。
- 架构边界目前保持干净，因此不为潜在未来违规新增扫描脚本。

## Key Decisions

- 用户允许在收益明确时进行源码重构和代码精简，但不接受为了行数、风格或未来假设进行重构。
- Ponytail full：删除优先于新增，已有 helper 优先于新抽象，未经测量的性能优化不进入本阶段。
- 插件体系暂不处理。

## Notes

- 当前状态为 `in_progress`；源码精简与规范同步已经实施，等待最终 Trellis 收尾。
