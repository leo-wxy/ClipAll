# 插件运行与生命周期可靠性

## Goal

在不改变插件 Runtime v2 公开接口的前提下，修复三项已经由代码审查确认的可靠性缺口：
替换安装必须在新插件激活成功后才丢弃旧包；App 对 manifest 的实际校验必须与公开 schema
一致；Runner 必须在 JavaScript 执行期间限制内存日志，而不是执行结束后才截断。

## Background

- `PluginInstallationStore.commit` 在返回前通过 `defer` 删除整个 operation directory，替换时
  保存于其中的旧包和 receipt 也随之删除
  （`ClipAll/PluginHost/Installation/PluginInstallationStore.swift:98-113,125-143`）。
- `PluginLifecycleController.install` 在文件 commit 返回后才调用 `activate(installed)`；激活失败
  虽尝试重新激活旧的内存 package，但磁盘旧包已经无法恢复，重启后仍会载入新包
  （`ClipAll/PluginHost/Lifecycle/PluginLifecycleController.swift:170-209`）。
- v2 schema 要求 `examples` / `exclusions` 最多 12 项且单项不超过 240 字符、text
  `defaultValue` 不超过 4096 字符、runtime entry 以大小写敏感的 `.js` 结尾；Mapper 当前会静默
  截断 examples、忽略 exclusions 限制、漏掉 text 默认值长度，并接受 `.JS`
  （`PluginSDK/Schemas/plugin-manifest-v2.schema.json:80-85,141-149,227-236`，
  `ClipAll/PluginHost/Manifest/ExternalPluginManifestMapper.swift:149-150,270-281,309-317`）。
- Runner bootstrap 的 `append` 会把所有 `console` 调用加入数组，100 条/500 字符限制只在执行结束
  读取结果时生效；正式执行即使 `capturesLogs == false` 也会先累计再丢弃
  （`ClipAllPluginRunner/JavaScriptPluginRuntime.swift:121-129,165-219`）。
- Runtime v2、`handler(text)`、`App.getPluginEnv(pluginID)`、配置真相源和卸载清理主体已经在
  `68f574d` 落地，本任务不重新设计这些合同。

## Requirements

### R1. 替换安装保留可回滚窗口

- 安装 Store 在新包与 receipt 写入后返回一个单次 pending transaction；旧包、旧 receipt 和
  operation directory 必须保留到生命周期明确 finalize。
- 生命周期只能在新插件完成配置注册和 registry 激活后 finalize；随后才更新 managed state、
  enabled state 和 capability references。
- 新插件激活失败时，Store rollback 必须删除新包与新 receipt，并原样恢复旧包与旧 receipt；
  生命周期同时恢复旧 descriptor 和 registry。
- 首次安装激活失败时不得留下安装包、receipt、配置 descriptor、registry 或 managed state。
- disabled 插件没有激活步骤，文件 commit 校验成功后可以立即 finalize。
- pending transaction token 只能 finalize 或 rollback 一次；普通 staging 清理不得提前删除仍在
  pending 的 backup。
- Store 在 operation directory 写入最小 `transaction.json` 阶段记录；旧包先完整复制到 backup，
  再切换 Installed。重启时 `committing/backedUp/rollingBack/restored/pending` 必须分别恢复旧版、
  清理终态或保留已经完成 package + receipt 的新版本，不能无条件删除 orphan backup。
- commit 必须重新校验 staged package，且 fingerprint 与 pluginID 必须和 prepare 结果一致；
  prepare 后被替换的合法 package 也必须拒绝。
- 生命周期注册新 descriptor 前保存原始配置值；激活或文件 rollback 失败时恢复原值，避免字段
  类型变化把用户配置覆盖为默认值。
- 不把文件事务复制到 Lifecycle，不新增通用事务框架或单实现 protocol。

### R2. Manifest schema 与 Mapper 使用同一限制

- Mapper 对 `examples` 和 `exclusions` 执行与 schema 相同的数量和单项长度校验；超限时明确
  返回 `manifest_limit` 和准确 JSON location，不得静默截断。
- text 字段的字符串默认值不得超过 4096 字符。
- runtime entry 只接受大小写敏感的 `.js` 后缀，与 schema 保持一致。
- `exclusions` 在 v2 中继续作为经过校验的 manifest 声明，不新增 `CapabilityDescriptor` 字段、
  UI 或自然语言路由逻辑；SDK 文档明确其当前不参与执行和推荐。
- 使用现有 Decoder、Mapper 和 `CoreVerification` 覆盖这些边界，不引入 JSON Schema 运行时依赖。

### R3. Runner 在写入时限制日志

- `capturesLogs == false` 时 bootstrap 不保存任何 console 日志。
- `capturesLogs == true` 时最多保存 `PluginRuntimeLimits.maximumLogEntries` 条；达到上限后忽略
  后续日志。
- 每条日志加入数组前即限制为 `maximumLogEntryCharacters` 个字符，保持现有 level 前缀与顺序。
- 输出边界仍可保留防御性截断，但不能依赖执行结束后的截断控制内存。
- 不记录选中文字、配置值或返回正文到宿主日志，不增加新的日志封装。

### R4. 回归验证与兼容性

- 生命周期 verification 覆盖 pending commit 的 finalize 与 rollback：替换回滚后旧 fingerprint、
  version、receipt 和 staging 状态恢复；首次安装 rollback 后不留包。
- 生命周期 verification 覆盖 backup、rollback 和完整 pending 三种重启恢复语义，并覆盖 prepare
  后 staged fingerprint 变化与配置类型变化后的失败恢复。
- Core verification 覆盖 examples/exclusions 数量和长度、text 默认值长度及 `.JS` entry 拒绝。
- Runtime verification 覆盖大量/超长 console 日志以及 `capturesLogs == false`。
- `Scripts/check-version.sh`、`Scripts/verify-all.sh`、`swift build --target ClipAll` 和
  `git diff --check` 必须通过。
- 使用稳定 `ClipAll Local Development` 身份安装到 `/Applications/ClipAll.app`，由用户验收正常
  导入、替换、配置、调试和执行路径。

## Acceptance Criteria

- [x] 新插件激活成功前旧安装包与 receipt 不会被删除。
- [x] 替换 transaction rollback 后，`validateInstalled` 返回旧 fingerprint/version，receipt 与旧包一致。
- [x] 首次安装 transaction rollback 后，Store 报告插件未安装且 staging 无残留。
- [x] transaction finalize 后新包可正常载入，旧 backup 与 staging 被清理。
- [x] 生命周期激活失败分支调用 rollback，并恢复旧配置 descriptor 与 registry；不会更新 managed state。
- [x] App 在 backup、rollback 或 pending 阶段退出后，下一次 Store 操作恢复到完整旧版本或完整新版本。
- [x] prepare 后 package 内容或 pluginID 改变时 commit 明确拒绝，不混用旧生命周期元数据。
- [x] 替换包改变配置字段类型且激活失败时，原始配置值保持不变。
- [x] 超过 schema 限制的 examples、exclusions、text 默认值和大写 `.JS` entry 均被 Mapper 明确拒绝。
- [x] 合法 examples 不被截断；exclusions 不触发 UI、路由或 Runtime 新行为。
- [x] 开启日志时 Runner 最多返回 100 条、每条最多 500 字符，且执行期数组不再无界增长。
- [x] 关闭日志时 Runner 不累计也不返回 console 日志。
- [x] Runtime v2、`handler(text)`、`App.getPluginEnv(pluginID)`、配置隔离和权限边界保持不变。
- [ ] 全量自动验证、主 App 构建、签名安装通过，用户完成插件专项验收。

## Out of Scope

- 为外置 JavaScript 插件开放 secret；为当前不支持的 external secret 增加跨 Keychain/文件原子事务。
- 插件签名、作者身份、公证、市场、自动更新、网络/文件/剪贴板/Accessibility API 或自定义 UI。
- 执行 generation、停用/卸载时的 in-flight task 取消；没有现存竞态证据时不提前建设。
- 插件脚手架、模板生成器或新的测试框架。
- 修改 Runtime v2 handler、配置 API、配置持久化 key、manifestVersion、protocolVersion、App 版本或 CI。
- 通用数据库事务、跨 Keychain/文件 journal 或可扩展 transaction framework；本阶段记录仅属于
  `PluginInstallationStore` 的 `.Staging` 文件恢复。

## Key Decisions

- 保留 `PluginInstallationStore` 作为文件事务唯一所有者，Lifecycle 只持有 pending token 并决定
  finalize/rollback。
- 不通过“激活通常不会失败”忽略回滚缺口；failure branch 必须有可执行回归。
- Mapper 是 App 导入边界，必须显式实现公开 schema 的限制；不加入第三方 schema evaluator。
- exclusions 当前没有消费者，验证后丢弃比新增无用领域字段更小、更诚实。
- 外置 v2 不支持 secret，因此本阶段不扩建 Keychain snapshot/restore 事务。

## Risks And Deferred Items

- `.Staging/transaction.json` 是 Store 私有恢复记录，不是 SDK 或稳定持久化合同；完整 pending
  在重启后保留新包，未完成 backup/rollback 阶段恢复旧包，`restored` 只完成残留清理。
- rollback 自身的文件恢复失败必须返回 `transactionFailed`，不得声称旧版本已保留。
- `08-14-plugin-runtime-config-api` 仍需用户完成真实 App 插件专项验收后才能归档；本任务不替代其验收。

## Notes

- 已完成实现和自动质量门，任务保持 `in_progress`，等待稳定签名安装后的真实 App 专项验收。
