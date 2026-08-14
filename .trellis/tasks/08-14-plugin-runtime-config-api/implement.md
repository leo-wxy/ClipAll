# 插件 Runtime 与配置接口 v2 实施计划

## Preconditions

- 用户已确认 PRD 中 handler、配置、secret、卸载和字段写入决策。
- 用户审核本 `design.md` 与 `implement.md` 后，才运行 `task.py start`。
- 实施前加载 backend/frontend/cross-layer 规范；不修改用户已有
  `.trellis/tasks/00-join-clipall/`。
- 本任务不改 VERSION、CI、依赖、签名或发布配置。

## Step 1. Establish Baseline

- [ ] 运行 `Scripts/check-version.sh`、`Scripts/verify-core.sh`、
  `Scripts/verify-plugin.sh`、`Scripts/verify-runner-client.sh`。
- [ ] 记录 `handler(request)`、Runtime v1、manifest v1、配置 direct-read 和卸载保留分支的
  静态搜索基线。

## Step 2. Switch Manifest And Process Contracts To v2

修改：

- `ClipAllPluginProtocol/PluginRuntimeProtocol.swift`
  - protocolVersion 改为 2。
  - input 改为 pluginID + text + configuration，删除 locale/timezone。
- `ClipAll/PluginHost/Manifest/ExternalPluginManifestMapper.swift`
  - 只接受 manifestVersion 2，更新 v2 错误文案。
- `ClipAll/PluginHost/Manifest/ExternalPluginManifestDecoder.swift`
  - schema 错误文案同步到 v2。
- `PluginSDK/Schemas/plugin-manifest-v2.schema.json`
  - 从当前 schema 迁移并把 manifestVersion 固定为 2。
- `Plugins/Examples/TimestampTools.clipallplugin/plugin.json`
  - 切换 manifestVersion 2。
- 删除当前 SDK 的 v1 schema，避免同时维护两个不兼容入口。
- `CoreVerification.swift` 增加 v1 manifest 明确返回 `manifest_version` 与正确 location 的回归。

定向验证：

```bash
Scripts/verify-core.sh
Scripts/check-version.sh
```

## Step 3. Keep One Configuration Truth Source

修改：

- `PluginConfigurationStore.swift`
  - 保留 typed field read 与 resolved environment 两种既有入口；两者继续共享 pluginID
    隔离、默认合并和校验，不新增 facade。
- `ExternalPluginExecutor.swift`、`PluginDebugSession.swift`
  - 使用同一 environment 转为 Runtime configuration map。

定向验证：

- 在现有 `OverlayExecutionVerification.swift` 增加 isolated UserDefaults 场景：默认合并、
  sibling 保留、错误类型、stale 过滤和 remove。
- `Scripts/verify-overlay-state.sh`。

## Step 4. Install JavaScript Runtime API v2

修改：

- `ClipAllPluginRunner/JavaScriptPluginRuntime.swift`
  - 通过闭包安装不可变 `App.getPluginEnv(pluginID)`。
  - 不暴露 raw request global。
  - handler 仅传 text。
- `ClipAllPluginRunner/main.swift`
  - 先解 protocol envelope，再解完整 v2 request；fallback response 版本同步为 2。
- `ExternalPluginExecutor.swift`、`PluginDebugSession.swift`
  - 生成 v2 request，删除 locale/timezone 注入。

定向验证：

- `PluginRuntimeVerification.swift` 解码并断言 manifestVersion 2 + stable plugin id，覆盖 text
  参数、own/other ID、空 env、冻结对象、raw request 隐藏和真实 v1 JSON 协议拒绝。
- `PluginRunnerClientVerification.swift` 所有 mock response 切换 v2，保留错误矩阵。
- `Scripts/verify-runner-client.sh`、`Scripts/verify-plugin.sh`。

## Step 5. Make Uninstall Purge Plugin Data

修改：

- `PluginSecretStore.swift`
  - 限定 service 枚举 account attributes，用精确 `<pluginID>.` 边界过滤后逐项删除。
- `PluginLifecycleController.swift`
  - 注入最小 secret-delete closure，避免新 service/protocol。
  - `uninstall(pluginID:)` 删除保留配置分支；先清理异常/陈旧 secret，成功后再改变 registry
    和包，包卸载成功后删除普通配置。
  - bundled TimestampTools 修复允许 `manifest_version` 触发 v2 自动替换。
- `AppEnvironment.swift`
  - 传入同一个 secret store。
- `PluginsSettingsView.swift`
  - 删除 Toggle、布尔 model 和布尔回调；说明卸载会清除配置。
- `Verification/PluginLifecycleVerification.swift`、`Scripts/verify-lifecycle.sh`
  - 把生命周期验证从安装目录事务扩展到 controller 卸载编排，并补齐所需现有源码编译清单。

定向验证：

- 静态确认不存在 `removesConfiguration`。
- 扩展生命周期 verification：secret-delete closure 收到精确 pluginID、成功卸载删除普通配置；
  closure 失败时包、registry、managed state 和普通配置均不变。
- Keychain account 精确边界使用纯匹配 helper 验证 `com.foo` 不命中 `com.foo-bar`；不在 CI
  写入用户真实 Keychain service。
- `Scripts/verify-lifecycle.sh`。

## Step 6. Migrate SDK, Example And Fixtures

修改：

- 新增 `Docs/PluginSDK/manifest-v2.md`、`runtime-v2.md`，删除当前 v1 文档。
- 更新 `Docs/PluginSDK/README.md`、`debugging.md`、`Docs/Architecture.md`、根 `README.md`。
- `TimestampTools/main.js` 改为 `handler(text)` + `App.getPluginEnv(stableID)`，system timezone
  通过标准 `Intl` 获取。
- fixtures 与 `PluginRuntimeVerification` 删除宿主时区字段，保留 UTC 和标准环境覆盖。
- system fixtures 只断言当前标准环境成功；删除依赖宿主注入 New York 时区的 DST
  gap/fold cases。

定向验证：

```bash
Scripts/verify-plugin.sh Plugins/Examples/TimestampTools.clipallplugin
Scripts/verify-core.sh
```

## Step 7. Cross-Layer Static Audit

必须无遗留：

```bash
rg -n 'handler\(request\)|__clipallRequest|localeIdentifier|systemTimeZoneIdentifier|manifestVersion.?1|protocolVersion.?1|removesConfiguration|外置插件 v1|v1 schema' \
  ClipAll ClipAllPluginProtocol ClipAllPluginRunner PluginSDK Plugins Docs Verification README.md
```

允许命中仅限明确说明“v1 被拒绝”的 migration/verification 文案。

## Step 8. Full Quality Gate

```bash
Scripts/check-version.sh
Scripts/verify-all.sh
env CLANG_MODULE_CACHE_PATH="$PWD/.swift-module-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.swift-module-cache" \
  swift test --disable-sandbox --build-system native
env CLANG_MODULE_CACHE_PATH="$PWD/.swift-module-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.swift-module-cache" \
  swift build --target ClipAll --disable-sandbox --build-system native
git diff --check
```

- 加载 `trellis-check` 做全范围 spec、PRD、design、协议与 UI 复核。
- 任何 cross-layer v1/v2 漂移先修复，再进入安装。

## Step 9. Install And Manual QA

```bash
Scripts/install-local-app.sh
```

用户在 `/Applications/ClipAll.app` 验收：

1. Search 与 Translation 配置读取、修改和重启保持正常。
2. Translation API Key 仍保存在 Keychain，Runtime/日志不可见。
3. TimestampTools v2 导入、配置、两项能力、调试器和 fixtures 正常。
4. manifest v1 测试包得到明确版本错误。
5. 卸载 TimestampTools 后配置不保留；重新安装恢复 manifest 默认值。
6. 已安装的 bundled TimestampTools v1 副本升级后自动替换为 v2。

## Finish Gate

- 用户明确测试通过前，不 commit、不归档、不声称完成。
- 测试通过后加载 `trellis-update-spec`，记录 Runtime v2、pluginID 环境与卸载清理合同。
- 提交前只纳入本任务文件；`.trellis/tasks/00-join-clipall/` 保持未跟踪且不提交。

## Risk And Rollback Points

- manifest/protocol/示例必须作为一个合同批次切换；任何定向验证失败都在该 Step 内修复。
- JavaScript raw request 隐藏与 env 冻结是安全门槛，不以文档说明替代验证。
- Keychain 查询必须使用精确 pluginID account 边界；不得使用模糊 substring。
- 不增加兼容 shim、配置 facade、新测试框架或第二套持久化。
