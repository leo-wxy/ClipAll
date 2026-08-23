# 插件运行与生命周期可靠性实施计划

## Preconditions

- 用户审核本任务 `prd.md`、`design.md` 和 `implement.md` 后，才运行 `task.py start`。
- 实施前加载 backend quality、frontend quality/component 与 cross-layer 规范。
- 不修改 `.trellis/tasks/00-join-clipall/`，不改 VERSION、CI、依赖、签名或 Runtime v2 API。

## Step 1. Establish Baseline

- [x] 运行 `Scripts/check-version.sh`、`Scripts/verify-core.sh`、`Scripts/verify-plugin.sh`、
  `Scripts/verify-lifecycle.sh`。
- [x] 记录 `commit`/`activate` 顺序、Mapper 已知宽松点和 bootstrap append 当前行为。

## Step 2. Add Pending Installation Transaction

修改：

- `ClipAll/PluginHost/Installation/PluginInstallationStore.swift`
  - 增加最小 pending token 与 Store 私有 transaction record。
  - commit 成功后保留 backup；新增单次 finalize/rollback。
  - 旧包先复制 backup，再切换 Installed；`.Staging/transaction.json` 记录恢复 phase。
  - staging cleanup 排除当前 pending，并恢复 orphan backedUp/rollingBack/pending operation。
- `ClipAll/PluginHost/Lifecycle/PluginLifecycleController.swift`
  - 使用 pending package 激活；成功 finalize，失败 rollback 后恢复 previous descriptor/registry。
  - 激活前保存配置值快照，失败后原样恢复。
  - disabled 插件在文件校验成功后直接 finalize。
- `ClipAll/Infrastructure/Persistence/PluginConfigurationStore.swift`
  - 提供 pluginID 级原始值恢复，不改变 storage key 或字段合同。
- `Verification/PluginLifecycleVerification.swift`
  - 首次安装 rollback、替换 rollback、finalize、token 单次消费与三种重启恢复回归。
  - 覆盖 staged fingerprint 变化与配置类型变化后的激活失败恢复。

定向验证：

```sh
Scripts/verify-lifecycle.sh
```

## Step 3. Align Manifest Mapper With Schema

修改：

- `ClipAll/PluginHost/Manifest/ExternalPluginManifestMapper.swift`
  - 校验 examples/exclusions 数量和单项长度。
  - 校验 text default 最大长度。
  - `.js` 后缀改为大小写敏感。
  - 删除 examples 静默 `prefix(12)`。
- `Verification/CoreVerification.swift`
  - 使用 manifest JSON 变体覆盖所有新增拒绝边界及 code/location。
- `Docs/PluginSDK/manifest-v2.md`
  - 明确 exclusions 当前只校验，不参与 UI、推荐或 Runtime。
- `Docs/PluginSDK/README.md`
  - 修正 exclusions 会参与宿主匹配的旧描述。

定向验证：

```sh
Scripts/verify-core.sh
```

## Step 4. Bound Logs At Append Time

修改：

- `ClipAllPluginRunner/JavaScriptPluginRuntime.swift`
  - bootstrap 接收 capture flag 与限制值。
  - 未开启时不保存；达到条数后忽略；push 前截断。
- `Verification/PluginRuntimeVerification.swift`
  - 覆盖大量、超长、顺序、level 和 capture-disabled 场景。

定向验证：

```sh
Scripts/verify-plugin.sh
Scripts/verify-runner-client.sh
```

## Step 5. Static Contract Audit

- [x] 确认没有新增 transaction protocol/facade、schema dependency 或日志 service。
- [x] 确认 `handler(text)`、`App.getPluginEnv`、protocolVersion/manifestVersion 2 未变化。
- [x] 确认 exclusions 没有进入 Router/UI/Runtime，Runner 没有宿主新权限。
- [x] `git diff --check`。

## Step 6. Full Quality Gate

```sh
Scripts/check-version.sh
Scripts/verify-all.sh
env CLANG_MODULE_CACHE_PATH="$PWD/.swift-module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.swift-module-cache" swift build --target ClipAll --disable-sandbox --build-system native
git diff --check
```

- 受限沙箱若在 `PasteboardCreate` 失败，使用同一未修改的 `Scripts/verify-all.sh` 在沙箱外复核。
- 加载 `trellis-check` 做全范围 cross-layer 复核；P0/P1 未清零不得安装。
- [x] `Scripts/check-version.sh` 通过。
- [x] `Scripts/verify-all.sh` 在真实 macOS 环境通过；受限沙箱失败仅为私有 Pasteboard 能力限制。
- [x] `swift build --target ClipAll --disable-sandbox --build-system native` 通过。
- [x] 最终 Trellis cross-layer 核对无产品 P0/P1。

## Step 7. Install And Manual QA

```sh
Scripts/install-local-app.sh
```

- [x] 稳定签名身份 `ClipAll Local Development` 已确认。
- [x] 主 App 与内嵌 Runner 的签名和 designated requirement 已核验，当前构建已安装并启动。
- [ ] 等待用户完成以下真实 App 专项验收。

用户在 `/Applications/ClipAll.app` 验收：

1. 导入 TimestampTools，配置、正式执行和调试器正常。
2. 用同 ID 新包执行替换，替换后能力与配置仍正常。
3. 卸载再安装恢复 manifest 默认值。
4. 普通取词、Search 和 Translation 无回归。

## Finish Gate

- 用户明确测试通过前，不 commit、不归档、不声称完成。
- 通过后按 `trellis-update-spec` 判断是否补充 pending install transaction 合同。
- 提交只纳入本任务文件；`.trellis/tasks/00-join-clipall/` 保持未跟踪。

## Rollback Points

- Step 2 文件事务与 Lifecycle 必须作为一个批次验证，不能只提交 pending API。
- Step 3 每个新限制都必须有 Mapper 回归，避免 schema 再次漂移。
- Step 4 必须保留现有 response logs 格式和错误 payload。
