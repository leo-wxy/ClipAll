# 实施计划：能力外显与插件交互

## Success Standard

在完整 Xcode 环境下，从全新构建启动 ClipAll 后，用户能授权辅助功能权限，在支持 Accessibility 的应用中选中文字并完成复制、搜索和系统翻译；用户还能导入独立的 `TimestampTools.clipallplugin`，配置、调试并执行日期/时间戳互转，随后停用、重新启用或卸载它。固定能力、推荐行、“更多能力”和能力中心遵守 PRD 的有界结构，异常插件不会拖垮主 App，自动化测试和手动主流程验收均通过。

## Preconditions

- 安装完整 Xcode，包含 macOS 15 或更新 SDK；当前机器只有 Command Line Tools，现阶段无法进行标准 macOS App 构建和 UI 运行验证。
- 进入实施前由用户明确批准最终规划摘要，再运行 `task.py start`。
- 实施开始后先加载 `trellis-before-dev`；当前项目规范仍是占位内容，建立首批真实约定后在完成阶段通过 `trellis-update-spec` 回写。
- 本任务由主会话实施；子代理仅可用于宽范围探索或独立核验，不负责修改产品代码。

## Ordered Implementation Checklist

### 1. Bootstrap Native macOS Project And Targets

- [ ] 创建 `ClipAll.xcodeproj`、ClipAll App、`ClipAllPluginRunner` helper、ClipAllTests 和 PluginRunnerTests targets；SwiftPM 同步提供可在当前 CLT 环境编译核心源码的验证入口。
- [ ] 设置 Swift、macOS 15 deployment target、bundle identifier 和共享 scheme。
- [ ] 建立菜单栏 accessory app 生命周期及能力中心窗口入口。
- [ ] 在菜单栏实现“启用 ClipAll”状态开关；停用后立即停止 selection monitor 并关闭当前浮层。
- [ ] 明确关闭 App Sandbox，并在工程说明中记录 Accessibility 取词原因。
- [ ] 按 `design.md` 建立 App/Domain/BuiltInPlugins/PluginHost/Infrastructure/Features、独立 runner、PluginSDK、Plugins/Examples 与 Docs/PluginSDK 目录。
- [ ] App bundle 构建时复制 runner 和可导入的时间工具示例包，但不把示例脚本编译或静态注册进 App target。
- [ ] 完成空工程 build/test，作为后续步骤基线。

### 2. Build Domain And Persistence Foundation

- [ ] 实现 `SelectionContext`、能力标识、descriptor、执行类型、输出和错误模型。
- [ ] 实现 `CapabilityRegistry` 的插件级原子注册/注销、进程内 `ClipAllPlugin` 协议，以及内置搜索/翻译和外置时间能力的稳定 ID。
- [ ] 实现 choice、toggle、text、secret 四类插件配置声明、条件显示和按 `pluginID + fieldID` 隔离的 `PluginConfigurationStore`。
- [ ] 实现 Keychain-backed `PluginSecretStore`；任何 API key 不得进入 `UserDefaults` 或日志。
- [ ] 实现 `SettingsStore`：默认固定 `[search, translate]`、最多 4 项、最近使用上限、应用启停、快捷键、开发者模式和插件 enabled 状态；插件字段值不得写入全局 store。
- [ ] 为固定能力去重、缺失能力过滤、默认值和持久化迁移补单元测试。

### 3. Implement External Plugin SDK And Lifecycle

- [ ] 定义 `plugin.json` v1 DTO、机器可读 JSON Schema、domain mapper、稳定错误 code 和 SDK 文档。
- [ ] 实现包校验：后缀、UTF-8/JSON、manifest/host 版本、反向域名 ID、capability 前缀、handler、配置默认值、路径规范化、符号链接、文件数量和体积限制。
- [ ] 实现 `PluginInstallationStore` 的 staging、原子安装、receipt/hash、显式替换、失败回滚和源包只读保证。
- [ ] 实现插件 enable/disable/uninstall；注销时取消任务并清理活动固定/最近引用，卸载默认保留配置且支持显式删除插件数据。
- [ ] 实现 `ClipAllPluginRunner` 单次 JSON 协议、无原生桥接 JavaScriptCore context、输出二次校验、超时终止和大小限制。
- [ ] 为合法/恶意包、替换失败、卸载策略、JS 异常、超时、崩溃、非法输出和进程状态隔离补测试。

### 4. Implement Permission And Selection Capture

- [ ] 封装辅助功能信任检查、权限引导和重新检查操作。
- [ ] 实现 system-wide focused element、selected text、selected range 和 bounds 读取。
- [ ] 实现全局鼠标抬起监听、防抖、重复选区抑制及可配置全局快捷键入口。
- [ ] 将 AX 错误映射为权限、无选区、不支持、超时和来源失效状态。
- [ ] 通过协议/fake 测试捕获成功、无 bounds 回退、旧内容禁止复用和 AX 错误分支。

### 5. Build Overlay Shell And Copy Flow

- [ ] 创建复用、默认不抢焦点的 `NSPanel` 和 SwiftUI 根视图。
- [ ] 实现选区下方/上方选择、屏幕边界 clamp 和 bounds 缺失回退。
- [ ] 实现 `SelectionOverlayStore` 状态机和 context ID 过期保护。
- [ ] 实现固定首位的复制操作、剪贴板写入、成功反馈和关闭策略。
- [ ] 添加定位纯函数及状态转换单元测试。

### 6. Implement Built-in Search And Translation

- [ ] 实现搜索提供方 URL 模板、查询编码和 `NSWorkspace` 默认浏览器打开。
- [ ] 搜索插件声明 Google、Bing、DuckDuckGo choice 配置，并让每次执行读取当前插件值。
- [ ] 使用 macOS 15 `TranslationSession` 实现系统翻译 provider。
- [ ] 实现 `TranslationProviderRegistry` 和 OpenAI-compatible AI provider，读取 endpoint、model 与 Keychain API key。
- [ ] 实现目标语言设置、模型准备/下载、加载、成功、失败和不可用状态。
- [ ] 保证取消或旧 context 的搜索/翻译结果不能修改当前浮层。
- [ ] 测试 URL 编码、设置切换、翻译错误映射和过期结果。

### 7. Implement External Timestamp Tools Reference Plugin

- [ ] 在 `Plugins/Examples/TimestampTools.clipallplugin` 创建独立 `plugin.json`、`main.js`、README 和 fixtures；主 App 中不保留时间转换 Swift 执行器。
- [ ] manifest 一次声明 `时间戳 → 日期` 与 `日期 → 时间戳` 两个独立能力及各自 handler。
- [ ] 实现 10 位秒级、13 位毫秒级 Unix 时间戳的严格识别与边界校验。
- [ ] 实现 ISO 8601 和明确常见格式的日期解析；无时区输入使用系统时区并在结果中标注。
- [ ] 时间工具声明系统/UTC 时区和标准/ISO 8601/中文显示格式，并让每次 runner 请求读取当前插件配置；显示格式不改变严格解析规则。
- [ ] 输出本地时间、UTC、秒级和毫秒级结果，并提供逐项复制操作。
- [ ] 为 descriptor 补齐用途、内容类型、示例、排除项、插件归属和执行形态。
- [ ] 通过 SDK 验证器与 runner fixture 测试秒与毫秒、两种时区、三种显示格式、闰日、偏移、越界、无效和歧义输入。

### 8. Implement Capability Routing And Recommendation

- [ ] 实现语言、URL、邮箱、代码、地址倾向、长度和普通文本特征提取。
- [ ] 实现 exclusions、内容类型、语言差异、声明关键词、阈值和稳定 tie-break。
- [ ] 排除已固定能力后生成 1 个推荐，并产生短匹配原因。
- [ ] 实现推荐行的隐藏、显示、键盘焦点和显式执行行为。
- [ ] 使用同插件多能力与大量虚拟 descriptor 覆盖独立匹配、排序稳定和无可信候选测试。
- [ ] 验证 10/13 位时间戳只推荐转换到日期，受支持日期只推荐转换到时间戳，且优先于通用搜索。

### 9. Implement More Capabilities

- [ ] 建立固定最大高度的纵向命令面板和搜索输入。
- [ ] 空查询限制为最多 5 个匹配项和 3 个去重最近项。
- [ ] 非空查询匹配能力名称、用途和插件名称，并可找到全部已注册能力。
- [ ] 实现上下箭头、Return、Escape 和等价指针交互。
- [ ] 验证注入大量能力后浮层宽度、层级与最大高度不变。

### 10. Implement Capability Center And Plugin Developer Tools

- [ ] 建立可从菜单栏和浮层打开的 SwiftUI 标准窗口。
- [ ] 实现全部/固定/不可用筛选、搜索和能力详情。
- [ ] 实现固定、取消固定、拖动排序和最多 4 项限制。
- [ ] 展示能力描述、示例、插件归属、权限和可用状态。
- [ ] 根据插件配置 schema 自动渲染 choice、toggle、text 和 secret 控件，遵守条件显示；无配置插件不显示空配置区。
- [ ] 实现“导入插件”、安装确认、显式替换、启用/停用和卸载（保留/删除数据）流程。
- [ ] 将已导入的 `时间工具` 展示为一个外置插件及两个可独立固定的能力，首次安装时均不固定。
- [ ] 实现默认关闭的开发者模式、“加载未打包插件”、原子重新载入和移除开发引用。
- [ ] 实现插件调试器：manifest 问题、测试输入、内容特征、匹配分数/原因、配置、结构化输出、耗时、错误、内存日志与 fixtures。
- [ ] 验证能力中心修改会刷新浮层配置，但不会篡改当前选区 context。
- [ ] 建立标准 macOS `Settings` scene，以通用、能力、插件、开发者四个 tab 承载长期设置；菜单栏和 Command-comma 均可打开。
- [ ] 保证能力中心的发现/说明职责与设置页的配置/生命周期职责不重复，必要操作使用深链而非复制状态逻辑。

### 11. Accessibility, Privacy And Visual Polish

- [ ] 按选定视觉参考统一间距、层级、圆角、阴影、选中态和结果区。
- [ ] 补齐键盘焦点顺序、辅助功能标签、非颜色状态表达和 Reduce Motion 兼容。
- [ ] 检查 Release 日志不包含原文、译文或完整搜索 URL。
- [ ] 检查安装确认明确“未签名本地插件”，开发插件和普通插件状态不只靠颜色区分。
- [ ] 检查点击外部、Escape、来源变化、多屏和屏幕边缘行为。

### 12. Full Verification And Handoff

- [ ] 执行全部 build/test 命令并保存失败证据或通过结果。
- [ ] 按 PRD 的 AC1–AC21 做逐项验收，至少覆盖 TextEdit、Safari、权限拒绝、多显示器、键盘路径、设置四分区、插件导入/停用/卸载/调试、runner 故障和时间双向转换。
- [ ] 运行 `trellis-check` 做规范、构建、测试和跨层数据流检查。
- [ ] 使用 `trellis-update-spec` 写入实际 Swift/AppKit 目录、状态、错误处理和测试约定。
- [ ] 复核 App Sandbox 关闭、原文不落盘和外部搜索只在确认后发生。

## Validation Commands

安装完整 Xcode 后，在仓库根目录执行：

```bash
Scripts/verify-core.sh
Scripts/verify-plugin.sh Plugins/Examples/TimestampTools.clipallplugin
xcodebuild -version
xcodebuild -project ClipAll.xcodeproj -scheme ClipAll -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ClipAll.xcodeproj -scheme ClipAll -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

若 scheme 或项目名在工程创建时调整，必须同步更新本文件，而不是让验证命令静默失效。

## Manual Acceptance Matrix

| 场景 | 预期 |
|---|---|
| 首次启动、未授权 | 显示一次清晰权限说明；不读取或复用任何旧选区 |
| 菜单栏停用/启用 | 停用后不再自动弹出；重新启用后恢复捕获，设置和能力中心始终可访问 |
| TextEdit 指针选择 | 浮层靠近选区，复制/搜索/翻译可用 |
| Safari 可访问文本 | 能捕获时正常显示；目标不支持时安全退出 |
| 键盘选择 + 快捷键 | 使用与指针相同的浮层、路由和执行链路 |
| 屏幕边缘/多显示器 | 浮层保持在对应屏幕可见区域，优先不遮挡选区 |
| 搜索 | 确认后才打开默认浏览器，查询正确编码 |
| 翻译模型未安装 | 显示准备或下载状态；完成后在原浮层显示译文 |
| 导入时间工具 | 先校验并展示未签名/零权限摘要，确认后同时出现插件和两个能力 |
| 导入非法包 | 显示具体校验位置；Installed 与活动 registry 不发生半完成修改 |
| 停用/重新启用 | 两个时间能力同步退出/恢复；固定槽不被其他能力自动补位 |
| 卸载时间工具 | 取消任务并删除 App 安装副本，不碰原始包；配置按用户选择保留或删除 |
| 加载未打包插件 | 标记开发状态，可重新载入和移除引用；源码目录始终保留 |
| 插件调试器 | 能查看两个能力的匹配理由、运行 fixtures、结构化输出、错误和耗时 |
| Runner 超时/崩溃 | 只结束本次插件执行，主 App、复制、搜索和翻译继续可用 |
| 10 位/13 位时间戳 | 推荐具体的“时间戳 → 日期”能力并输出本地时间与 UTC |
| ISO 8601/常见日期 | 推荐具体的“日期 → 时间戳”能力并输出秒和毫秒 |
| 无时区/无效日期 | 无时区结果明确系统时区；无效或歧义输入不猜测 |
| 快速连续选择 | 旧翻译/匹配结果不能覆盖最新选区 |
| 大量虚拟能力 | 固定行和浮层宽度不变；空状态结果有上限；搜索可找全 |
| 仅键盘/仅指针 | 两条路径均能完成主流程 |

## Risky Files And Rollback Points

- `ClipAll.xcodeproj/project.pbxproj`：deployment target、target、scheme 与构建设置；修改前后都需执行空工程 build/test。
- App entitlement / `Info.plist`：App Sandbox、accessory app 和权限相关配置；错误设置会直接影响跨应用取词或应用生命周期。
- `PluginSDK/Schemas/plugin-manifest-v1.schema.json` 与 manifest DTO：属于外置插件兼容合同；字段变更必须保持 v1 兼容或提升 manifest version。
- `PluginInstallationStore`：负责 staging、原子替换与卸载；任何失败不得破坏当前安装，且绝不删除导入源/开发源。
- `ClipAllPluginRunner` 与 runtime protocol：不允许加入文件、网络、AppKit、Security 或 Accessibility 桥接；异常必须保持插件级隔离。
- `SelectionCaptureService` / `SelectionMonitor`：最容易产生重复触发、旧内容和兼容性问题；保持协议边界，可单独关闭自动鼠标触发。
- `SelectionOverlayCoordinator`：焦点和窗口层级可能干扰来源应用；保留“仅快捷键触发 + 非激活面板”作为局部回退。
- `SystemTranslationProvider`：模型下载与语言可用性依赖系统状态；失败时只禁用翻译，不阻塞复制和搜索。
- `TimestampTools.clipallplugin/main.js`：区域设置和时区会造成不可重复结果；通过显式字段解析、runner context 与 fixtures 隔离，并可直接停用示例插件。

## Deferred Follow-ups

- 插件作者签名/公证、在线身份、商店、自动更新、依赖解析和版本回滚 UI。
- 外置插件的网络、文件、剪贴板、Accessibility、自动化与自定义 UI 权限桥接。
- 更强的 runner 系统级 sandbox profile、内存硬限额与独立 XPC 服务评估；首版先以零桥接短进程和宿主超时建立边界。
- 基于语义模型的描述匹配和个性化推荐。
- 第三方翻译提供方、更多搜索提供方及按能力独立配置。
- 签名、公证、DMG、自动更新和正式直接分发。
- Mac App Store 可行性替代方案研究。
- 按应用/网站排除、剪切粘贴、替换原文、动作复制和跨设备同步等 PopClip 进阶能力。
