# 插件运行时配置接口解耦

## Goal

把“处理一次选中文字”和“读取插件配置”拆成两个稳定合同：外置插件 handler
只接收选中文字，插件按自身稳定 ID 通过通用运行时接口读取配置；设置 UI、生命周期与
Runner 继续共享一个配置真相源，不把配置存储细节或整份配置混入每次文本调用。

## Background

- 当前 JavaScript handler 接收完整 `request`，其中同时包含 `text`、
  `configuration`、`localeIdentifier` 和 `systemTimeZoneIdentifier`
  （`ClipAllPluginRunner/JavaScriptPluginRuntime.swift:27-65`）。
- `ExternalPluginExecutor` 和 `PluginDebugSession` 会在每次执行时从
  `PluginConfigurationStore.resolvedValues(pluginID:)` 读取配置并放入 Runtime request
  （`ClipAll/PluginHost/Runtime/ExternalPluginExecutor.swift:45-100`，
  `ClipAll/PluginHost/Development/PluginDebugSession.swift:149-177`）。
- `PluginConfigurationStore` 已经按 `pluginID + fieldID` 隔离配置，负责默认值合并、
  类型校验、持久化、重置、注销保留与删除数据
  （`ClipAll/Infrastructure/Persistence/PluginConfigurationStore.swift:23-125`）。
- 当前卸载确认默认不删除配置；`removesConfiguration == false` 时只注销 descriptor，
  UserDefaults 中的插件配置会保留。即使用户选择删除，生命周期目前也只调用
  `PluginConfigurationStore.removeData(pluginID:)`；`PluginSecretStore` 仅提供按 fieldID 删除
  Keychain 项的方法，卸载链路没有统一清理 secret
  （`ClipAll/PluginHost/Lifecycle/PluginLifecycleController.swift:251-278`，
  `ClipAll/Infrastructure/Security/PluginSecretStore.swift:31-85`，
  `ClipAll/Features/PluginManagement/PluginsSettingsView.swift:655-680`）。
- 设置表单通过该 Store 读取和写入字段，没有直接访问 UserDefaults；因此再增加一层只有
  一个实现的 `PluginEnvService`/protocol 只会换名字，不会减少真实存储耦合。
- `localeIdentifier` 当前没有 JavaScript 消费者；时间工具只使用配置和系统时区。
- 当前公开 SDK 是 Runtime v1，时间工具示例与本机已安装插件均使用 `handler(request)`。
- 产品尚未进入第三方插件开发阶段；本任务允许重新定义现有插件合同，不为旧 v1
  handler 保留兼容执行路径。
- 当前 manifest 与 Runtime protocol 都是 v1。由于 handler 参数语义无法从 JavaScript
  源码可靠推断，本任务将两层合同一起提升到 v2，让旧包在导入或进程协议边界明确失败。

## Requirements

### R1. 单一文本调用输入

- 新 Runtime 合同中，manifest 指定的 handler 只接收一个字符串参数 `text`。
- 配置、语言、时区和其他宿主状态不得作为 handler 参数的一部分。
- 宿主不再向外置插件注入 locale 或系统时区；插件需要这些信息时使用 JavaScript 标准
  运行环境，例如 `Date` / `Intl`。
- 选中文字仍受现有 65,536-byte 输入上限、超时和结果结构限制。

### R2. 固定配置读取接口

- Runner 向插件脚本暴露只读通用接口：
  `App.getPluginEnv(pluginID)`。
- `pluginID` 使用 manifest 的稳定 `id`，不使用可修改或可本地化的显示名称。
- 返回值是当前 manifest 默认值与用户覆盖值合并后的 JSON 对象；无配置时返回 `{}`。
- 返回值只包含当前 descriptor 声明的非 secret 字段；API Key 等 secret 永不进入
  `App.getPluginEnv(pluginID)` 或 Runner request。
- Runner 必须校验请求的 `pluginID` 等于当前执行插件，拒绝跨插件读取。
- 返回对象及其嵌套值对插件只读。

### R3. 统一配置真相源

- 复用现有 `PluginConfigurationStore` 作为配置真相源，不新增第二份缓存、持久化模型或
  单实现 facade。
- 内置 Search、Translation、Overlay 路由和外置插件 Runtime 必须共享同一个
  `PluginConfigurationStore`、pluginID 隔离、默认值合并和字段校验语义；内置 Swift 代码
  可以继续使用 Store 的 typed field 读取，不为统一 API 形状改成字典解析。
- 设置 UI 只通过 Store 的读取和字段写入方法操作配置，不直接访问 UserDefaults 或
  Runtime DTO；插件数据删除只由生命周期入口负责。
- 设置页使用 `pluginID + fieldID` 增量写入，不提交或覆盖整份配置 JSON；字段写入继续复用
  Store 现有的字段存在性、类型和 secret 校验。
- 设置页继续使用统一配置表单；普通字段写入 `PluginConfigurationStore`，secret 字段通过
  现有 `PluginSecretStore` 写入 Keychain。内置原生插件可以通过 `PluginSecretStore` 读取
  自身 secret，外置 JavaScript 插件不能读取任何 secret。
- 生命周期继续负责 descriptor 的 register/unregister；停用和升级必须保留配置。
- 卸载必须以 pluginID 为边界清除普通配置与 Keychain secret，不保留配置残留；卸载确认页
  删除“同时删除插件配置”选项。需要保留配置时，用户应停用插件而不是卸载。
- Runtime 只读取当前 descriptor 声明的非 secret 字段，不能把已删除字段的陈旧值发送给
  Runner。

### R4. 进程边界与公开 API 分离

- 宿主到 Runner 的内部 JSON 可以携带当前插件 ID 和只读配置快照，但这些字段不得直接
  暴露为 handler request。
- `App.getPluginEnv(pluginID)` 只读取 Runner 启动时注入的内存快照，不增加文件、网络、
  UserDefaults、Keychain 或回调宿主进程的能力。
- 插件不得通过 Runtime API 写回配置。

### R5. 开发与验证一致性

- 调试器、fixtures、正式执行使用同一 handler 与 Runtime API。
- 时间工具示例迁移到 `handler(text)` 和 `App.getPluginEnv(pluginID)`。
- SDK 文档、manifest schema、Swift DTO、Runner、示例插件和兼容测试必须同步更新到 v2。
- 配置验证至少覆盖默认值合并、插件 ID 隔离、未知字段/错误类型拒绝、字段更新不覆盖
  sibling、停用/升级保留、卸载删除和只读 Runtime 快照。

### R6. 合同重置

- 直接删除旧 `handler(request)` 公开合同，不增加 v1/v2 双分支、兼容 shim 或旧插件迁移层。
- 现有 SDK 文档、时间工具示例和 fixtures 全量切换到新合同。
- `manifestVersion` 与 Runner `protocolVersion` 均提升到 2；旧 v1 包必须在 manifest 校验
  阶段明确拒绝，旧 v1 进程请求必须在 Runner 协议边界明确拒绝。
- Runner 必须先读取最小 protocol envelope，再解码 v2 DTO，确保真实 v1 JSON 返回
  `unsupported_protocol`，而不是因 DTO 字段变化退化为 `invalid_request`。
- 只允许随 App 分发的 TimestampTools 旧安装副本自动替换为 v2；这不是通用 v1 执行兼容。
- 不通过源码探测猜测 handler 版本，不能让旧 handler 在错误参数下静默运行。

### R7. 统一配置体验

- 内置插件、已安装外置插件和开发引用使用同一配置表单、默认值合并、字段校验和可见性
  条件。
- 用户从设置页修改配置后，能力路由、原生能力执行、外置 Runner 和开发调试器读取到的
  必须是同一版本配置。
- 配置实现可以因安全级别使用不同持久化介质，但不得在 UI 中形成两套交互或生命周期。

## Acceptance Criteria

- [ ] 外置插件 handler 的唯一参数是选中文字字符串。
- [ ] 插件能通过自己的稳定 ID 调用 `App.getPluginEnv(pluginID)` 获得配置 JSON。
- [ ] 空配置插件获得 `{}`；有配置插件获得默认值与用户值合并后的对象。
- [ ] 插件无法读取其他 plugin ID 的配置，也无法修改返回配置。
- [ ] `App.getPluginEnv(pluginID)`、Runner request 和调试日志均不包含 secret。
- [ ] 内置 Translation 的 API Key 仍由统一设置表单编辑并存入 Keychain，原生执行路径可以
      正常读取。
- [ ] 设置 UI 修改配置后，下一次 Runtime 执行读取到一致结果。
- [ ] 设置页字段修改只更新目标 fieldID，不覆盖同插件的其他配置字段。
- [ ] 停用、重新启用、升级和开发引用重载保持配置；卸载后重新安装从 manifest 默认值开始。
- [ ] 删除插件数据时，pluginID 下普通配置与 Keychain secret 一并清除，不留下孤立数据。
- [ ] 卸载确认页不再提供保留配置选项。
- [ ] 时间工具全部 fixtures 通过，正式执行与调试器结果一致。
- [ ] UTC fixtures 保持精确断言；system timezone fixtures 使用标准 JavaScript 环境且不依赖
      宿主注入，跨机器稳定通过。
- [ ] 文件、网络、剪贴板、Accessibility、shell 和原生对象安全边界不扩大。
- [ ] Runner 不包含旧 `handler(request)` 兼容分支。
- [ ] manifest v1 包在导入时得到明确版本错误，Runtime protocol v1 请求得到明确协议错误。
- [ ] 外置 Runtime 不再携带或暴露 localeIdentifier/systemTimeZoneIdentifier。
- [ ] Search、Translation、Overlay、外置插件和调试器共享同一个配置真相源与 pluginID
      隔离语义。
- [ ] 内置、外置和开发插件使用同一配置表单体验。

## Out of Scope

- 插件在 Runtime 中写入配置。
- 向外置 JavaScript 插件开放 secret 读取能力。
- 文件、网络、剪贴板或其他宿主服务 API。
- 为未来存储后端预建第二个配置实现或通用依赖注入框架。

## Open Questions

无。
