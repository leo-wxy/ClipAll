# 插件 Runtime 与配置接口 v2 设计

## 1. Design Summary

本任务直接重置尚未对外稳定的插件合同：manifest 与 Runner protocol 同步提升到 v2，
JavaScript handler 只接收选中文字；配置通过只读 `App.getPluginEnv(pluginID)` 获取。
宿主复用现有 `PluginConfigurationStore` 和 `PluginSecretStore`，不新增 facade、第二份缓存或
兼容层。

```text
设置表单 --field write--> PluginConfigurationStore --resolved snapshot--+
                                                               |          |
内置能力 / Overlay <-------------- pluginID environment -------+          v
                                                           Runner request v2
SelectionContext.text ---------------------------------------------------->|
                                                                          v
                                                    App.getPluginEnv(id)
                                                    handler(text)
```

## 2. Scope And Boundaries

### Changed

- manifest contract v1 -> v2，旧 v1 包在导入阶段拒绝。
- Runner process protocol v1 -> v2，旧 v1 request 在 Runner 边界拒绝。
- JavaScript API：`handler(request)` -> `handler(text)`，新增只读
  `App.getPluginEnv(pluginID)`。
- 外置 Runtime 与 Debugger 共享 pluginID 级 resolved environment；内置 Swift 能力继续复用
  Store 的 typed field 读取。
- installed plugin 卸载固定清除普通配置与 Keychain secret。
- SDK 文档、TimestampTools、debug fixtures 与 verification 同步迁移。

### Unchanged

- manifest 声明式配置字段、路由规则、结构化结果和错误 payload。
- Runner 的 Pipe 传输、750ms timeout、请求/响应大小、日志和进程隔离。
- 外置插件仍无文件、网络、剪贴板、Accessibility、shell、原生对象或 secret 权限。
- 开发引用移除只移除引用和活动注册，不删除源码；配置继续保留以支持重载。
- App 版本号和发布流程不在本任务内调整。
- 不新增配置 reset UI；现有字段编辑与卸载删除已经覆盖本任务目标。

## 3. Version Contract

- `PluginRuntimeLimits.protocolVersion = 2`。
- `ExternalPluginManifestMapper` 只接受 `manifestVersion == 2`。
- 当前 SDK 入口指向 `manifest-v2.md`、`runtime-v2.md` 与
  `plugin-manifest-v2.schema.json`；v1 文档/schema 从当前 SDK 删除，避免暗示兼容。
- TimestampTools manifest 更新为 v2。`minimumClipAllVersion` 仍由现有 VERSION 同步规则管理。
- 不增加 `runtimeVersion`、双 Runner 分支、handler 参数探测或源码 shim；manifestVersion 已是
  现成的不兼容包合同。
- Runner 入口先解码只有 `protocolVersion` 的 envelope。版本不是 2 时直接返回
  `unsupported_protocol`；只有版本正确才解码完整 v2 DTO。
- `repairBundledPluginIfNeeded` 允许目标为随 App 提供的 TimestampTools 时，将
  `manifest_version` invalid 的旧安装副本替换为 v2。其他 v1 包仍按普通校验失败处理。

## 4. Native Configuration Contract

`PluginConfigurationStore` 继续是普通配置唯一真相源。现有 resolved 读取收敛为一个
pluginID 级方法，返回当前 descriptor 字段的默认值与用户值合并结果，并过滤 secret 与
已从 descriptor 删除的 stale field。

`resolvedValues(pluginID:)` 继续只服务需要整份 snapshot 的
ExternalPluginExecutor 与 PluginDebugSession。Search、Translation、Overlay 和配置表单保留
现有 typed field 读取；它们已经共享同一个 Store，不为 API 外观一致增加字典拆包。

设置写入继续使用 `pluginID + fieldID + typed value`，复用现有字段存在性、secret 和类型
校验；不提供整份 JSON 覆盖 API。本任务不新增 reset 按钮、view model 或配置 facade。

secret 字段仍由同一配置表单渲染，但只写 `PluginSecretStore` / Keychain。内置受信任代码
可读取自己的 secret；普通环境 snapshot、Runner request、JavaScript API 和日志都不含
secret。

## 5. Runner v2 DTO And Data Flow

内部 `PluginRuntimeInput` 仅包含：

```text
pluginID: String
text: String
configuration: [String: String | Bool]
```

移除 `localeIdentifier` 与 `systemTimeZoneIdentifier`。这些字段既不进入 handler，也不进入
`App.getPluginEnv`。插件需要本地日期/语言行为时使用 JavaScriptCore 提供的标准 `Date`、
`Intl` 等对象。

执行顺序：

1. 宿主从当前 `SelectionContext` 和 Store 生成 v2 request。
2. Runner 校验 protocol、文本上限并创建新的 JavaScript context。
3. Runner 先安装 console 与 Runtime API，再执行插件脚本。
4. `App.getPluginEnv(id)` 只允许 `id === request.pluginID`；其他 ID 抛稳定的
   `invalid_plugin_id` 错误。
5. 返回的 environment 递归冻结；`App` 自身不可写、不可配置。
6. Runner 调用 manifest handler，唯一参数为 `request.input.text`。
7. 输出继续经过现有 JSON、大小和结构校验。

## 6. JavaScript Encapsulation

不再把 `__clipallRequest` 放在全局对象。Runner 先求值一个安装函数，再从 Swift 侧以
pluginID 和 configuration 参数调用；安装函数将值捕获在闭包中，只把冻结后的 `App` 与
内存 console 暴露给插件脚本。

这保证插件无法通过调试全局变量绕过 `App.getPluginEnv` 读取内部 request，也无法修改
配置快照影响同次 handler 后续读取。

## 7. Uninstall And Secret Cleanup

installed plugin 的卸载入口简化为 `uninstall(pluginID:)`：

1. `PluginSecretStore` 在固定 service 下用 `kSecMatchLimitAll` 读取 account attributes，只保留
   `account.hasPrefix(pluginID.rawValue + ".")` 的精确边界，再按完整 account 删除；相似
   pluginID 不得命中。
2. secret 枚举或删除失败时，在 registry/文件系统变化前终止卸载并显示现有操作错误。
3. 保持现有 mutation guard、registry 注销和安装目录事务。
4. 安装目录卸载成功后，删除 capability recent/pinned 引用、plugin enabled state，以及
   `PluginConfigurationStore` 中该 pluginID 的字段元数据与持久值。
5. 卸载确认 UI 明确说明配置会一并删除，不再提供保留 Toggle。

停用、重新启用、替换升级和开发引用重载继续使用 register/unregister，保留配置。外置
manifest v2 仍不允许 secret，但清理入口同时处理 Keychain，避免现有或异常残留成为孤儿。

Keychain 删除失败不得被吞掉或伪装成完整成功；UI 使用现有操作失败通道显示错误。外置
manifest v2 不支持合法 secret，因此在 package mutation 前清理异常/陈旧 Keychain 项不会
删除受支持的插件配置。普通配置删除只在安装目录卸载成功后发生，避免包卸载失败时丢失
用户配置。未来若开放外置 secret，需重新设计跨 Keychain/文件事务，不沿用该简化顺序。

## 8. Debugger, Fixtures And TimestampTools

- 正式执行、调试器当前配置和 fixture override 都生成相同 v2 request。
- fixture 的 `configuration` 继续作为本次只读 environment，字段值必须由插件自行校验。
- fixture 删除宿主 `systemTimeZoneIdentifier` 注入。TimestampTools 的 system 模式通过
  `Intl.DateTimeFormat().resolvedOptions().timeZone` 获取当前 JavaScript 环境时区；UTC
  fixture 保持精确确定性断言。system fixture 只断言在当前标准环境成功并返回完整结果，
  不硬编码其他机器的 IANA 时区；删除依赖注入 New York 的 DST gap/fold fixture，不增加
  宿主私有测试 API。
- TimestampTools 两个 handler 改为 `handler(text)`，配置统一通过自己的稳定 plugin ID
  调用 `App.getPluginEnv`。

## 9. Validation Design

### Runtime

- handler 实际收到 string 而非 object。
- own pluginID 返回配置；无配置返回 `{}`。
- other/empty pluginID 抛错。
- configuration 与 `App` 无法改写，raw request 不存在于 global。
- v1 request 拒绝；现有 response/timeout/size/error 矩阵保持。

### Configuration

- default merge、field update 不覆盖 sibling、类型/unknown/secret 拒绝。
- stale field 不进入 environment，remove 清除持久值。
- 内置 typed reads、External executor 和 Debugger 使用同一个 Store 与 pluginID 隔离语义。

### Lifecycle / UI

- manifest v1 导入拒绝、v2 示例通过。
- 卸载 API 不再接受保留配置布尔值；确认页没有保留 Toggle。
- Keychain pluginID account 过滤使用精确边界并接受 item-not-found；删除失败在 package
  mutation 前终止。
- 生命周期验证通过可注入的最小 secret-delete closure 覆盖成功/失败顺序，不引入新的
  service/protocol 层。
- 全量 verification、SwiftPM build/test 和本地安装通过；用户在 Applications 副本验收配置、
  调试、执行与卸载。

## 10. Alternatives Rejected

- **新增 PluginEnvService/protocol**：只有一个 Store 实现，只增加转发层。
- **handler(text, env)**：仍把配置耦合进每次调用参数。
- **App.getPluginEnv() 无参数**：更短，但不符合已确认的稳定 pluginID 读取合同。
- **保留 v1 shim**：当前无第三方插件，双合同只增加不可测试分支。
- **把 secret 放进 env**：扩大外置脚本权限并破坏现有 Keychain 边界。
- **整份 JSON 写回**：可覆盖 sibling/stale 字段，重复 Store 已有校验。
- **把所有内置读取改成 environment 字典**：它们已经共享 Store，只会扩大类型拆包改动。

## 11. Rollback

本任务是一次原子合同切换，不能只回滚 Runner 或只回滚示例。回滚必须同时恢复 manifest
版本、protocol DTO、Runner、宿主 request、示例与 SDK。配置持久化 key 不改变，因此回滚
普通配置无需迁移；已执行卸载的数据删除不可恢复，验收前使用测试配置。
