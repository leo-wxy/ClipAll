# 插件运行与生命周期可靠性设计

## 1. Design Summary

本阶段保留 Runtime v2 和现有模块边界，只补三个缺口：

```text
Prepared import
  -> transaction.json: committing
  -> copy old package/receipt to backup
  -> transaction.json: backedUp
  -> pending file commit (new installed, old backup retained)
       -> activate/register succeeds -> finalize -> delete backup
       -> activate/register fails    -> rollback -> restore old package + receipt

plugin.json -> Decoder -> Mapper strict limits -> Domain definition

console.* -> append-time gate -> bounded in-memory logs -> response boundary
```

不创建通用 transaction framework、schema service、日志 service 或新的依赖。

## 2. Installation Transaction Boundary

### 2.1 Pending token

`PluginInstallationStore.commit` 返回最小的 `PendingPluginInstallation`：

- opaque token；
- 已重新校验且写入 Installed 的 `ValidatedExternalPluginPackage`。

Store 私有记录 token 对应的 destination、receipt、operation directory、是否存在旧包/receipt。
prepared token 在 commit 后失效，pending token 只能被 `finalize` 或 `rollback` 消费一次。

### 2.2 Store state transitions

```text
prepared
  -> committing: original files remain until backup copy and backedUp marker complete
  -> backedUp: switch Installed package/receipt
  -> pending:
       finalize: keep new package/receipt, delete operation backup
       rollback: write rollingBack, copy old files back, write restored, delete operation
```

operation directory 内的 `transaction.json` 只记录 pluginID、新版本/指纹、旧包/receipt 是否存在
以及当前 phase，不进入 SDK 或稳定数据合同。旧文件先复制到 backup，再删除 Installed 原件，避免
`committing` 中断时无法区分旧包位置。

`cleanupOrphanedStaging` 必须跳过当前 actor 内 pending operation；遇到 orphan transaction 时：

- `committing`：Installed 原件尚未切换，只清理 operation；
- `backedUp` / `rollingBack`：从完整 backup 恢复旧 package/receipt；
- `restored`：旧文件已恢复，只清理 operation；
- `pending`：新 package/receipt 与记录指纹完整匹配时保留新版本，否则恢复旧版本。

prepare 后 commit 会重新校验 staged package，并要求 pluginID 与 fingerprint 和 prepare 结果相同。

### 2.3 Lifecycle ordering

Lifecycle 在 commit 前保存 previous managed plugin、capability IDs 和原始配置值，然后：

1. `pending = installationStore.commit(...)`；
2. 如旧插件 enabled，注销旧 registry；
3. 注册新 descriptor；
4. 如应启用，激活 `pending.package`；
5. 激活成功或插件 disabled 后 `finalize(pending)`；
6. 更新 capability references、enabled state 和 managed plugin。

步骤 3/4 失败时：

1. `rollback(pending)` 恢复磁盘；
2. 恢复 previous descriptor；
3. previous enabled 时重新激活旧 package；首次安装则 unregister 新 descriptor；
4. 原样恢复 pluginID 对应的配置值快照，避免 descriptor 类型变化覆盖用户值；
5. 抛出原始激活错误；若文件 rollback 失败，则以 `transactionFailed` 为准，避免虚假声称旧包已恢复。

Registry 的批量 `register` 在写入前完成重复和 ownership 校验，保持现有原子性。不新增 registry
snapshot API。

## 3. Manifest Validation Parity

Mapper 继续是 App 的权威导入边界。新增的校验全部复用现有 `validateOptionalString` 和
`PluginValidationIssue`：

- examples count `<= 12`，逐项 `<= 240`；
- exclusions count `<= 12`，逐项 `<= 240`；
- text default 为 string 时 `<= 4096`；
- runtime entry 使用 `hasSuffix(".js")`，不做 lowercased 宽松匹配。

合法 examples 原样传给 `CapabilityDescriptor`，删除 `prefix(12)` 静默截断。exclusions 只完成
校验，不进入 Domain/UI/Router；SDK 明确它是保留声明字段，当前无行为。这样不为一个没有消费者
的字段扩张跨层模型。

验证使用现有 TimestampTools manifest 的 JSON 变体，经 Decoder + Mapper 走真实导入合同；每个
失败断言 code 与 location，不引入 runtime JSON Schema evaluator。

## 4. Bounded Runner Logs

bootstrap installer 接收：

- `capturesLogs`；
- `maximumLogEntries`；
- `maximumLogEntryCharacters`。

`append` 首先检查未开启或数组已满，直接返回；构造字符串后在 push 前截断。`logs(from:)` 继续
执行协议边界的 prefix/clip，作为防御性校验而不是内存控制机制。

Runtime verification 使用一个内存脚本循环写入超过上限的超长日志，断言数量、长度、顺序和
level 前缀；同一脚本在 `capturesLogs == false` 时返回空日志。

## 5. Compatibility And Security

- manifestVersion/protocolVersion 保持 2。
- handler 仍只接收 text；`App.getPluginEnv`、配置冻结与 pluginID 隔离不变。
- 安装目录、receipt 格式和配置持久化 key 不变，不需要迁移。
- Runner 不增加宿主回调、文件、网络、Keychain 或配置写入能力。
- 不把 exclusions 解析成自然语言规则，避免把文案当执行合同。

## 6. Validation Matrix

| 场景 | 预期 |
| --- | --- |
| 首次安装 pending rollback | 新包/receipt 删除，staging 清空 |
| 替换 pending rollback | 旧 package/receipt/fingerprint 完整恢复 |
| pending finalize | 新包有效，backup/staging 清空 |
| token 重复 finalize/rollback | 明确单次错误 |
| backedUp 后进程退出 | 重启后恢复旧 package/receipt |
| rollingBack 后进程退出 | 重启后继续恢复旧 package/receipt |
| 完整 pending 后进程退出 | 重启后保留指纹匹配的新 package/receipt |
| prepare 后 staged package 改变 | commit 返回 `unknownPreparation` |
| 配置字段类型变化后激活失败 | 原始用户配置值恢复 |
| examples/exclusions 超数或超长 | Mapper 返回精确 `manifest_limit` |
| text 默认值超过 4096 | Mapper 拒绝 `$.configuration[i].defaultValue` |
| entry 为 `MAIN.JS` | Mapper 拒绝 `$.runtime.entry` |
| 1000 条超长 console 日志 | 只保存前 100 条，每条最多 500 字符 |
| capturesLogs=false | 返回空数组且 bootstrap 不保存日志 |

## 7. Rollback

本阶段不改变 Installed package、receipt 或配置持久化格式，只在 `.Staging` operation 内增加
Store 私有 `transaction.json`。代码回滚必须同时恢复 recovery record、pending API、Lifecycle
配置快照调用和对应 verification；不扩大为数据库、跨 Keychain 文件事务或通用事务引擎。
