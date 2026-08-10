# Runner 客户端回归矩阵

## 范围与结论

当前 Runner 客户端的边界验证全部集中在
`Verification/PluginRunnerClientVerification.swift`，由
`Scripts/verify-runner-client.sh` 单独编译运行，并由
`Scripts/verify-all.sh` 纳入全量检查。测试目前只验证错误路径，没有一个成功响应的基线；也没有验证 stderr、stdin EOF 或通信期间的临时文件。

本次改成 `Pipe` 后，最小必补的是：在进程存活期间确认不创建宿主临时目录；同时制造大 stdout 与大 stderr，确认客户端并发排空而不死锁；让 fake runner 读取 stdin 至 EOF，确认客户端写完 request 后关闭 stdin。现有超时、取消、大小限制和非零退出断言应继续保留。

## 当前覆盖矩阵

| 场景 | fake runner / 输入 | 当前断言 | 覆盖判断 |
| --- | --- | --- | --- |
| Runner 缺失 | `root/missing` 不存在（`PluginRunnerClientVerification.swift:24-28`） | `runnerMissing` | 已覆盖；命中客户端 `isExecutableFile` 守卫（`PluginRunnerClient.swift:60-62`），不会启动进程 |
| stdout 非 JSON | `invalid-response.sh` 输出 `not-json` 后正常退出（验证文件 `:30-37`） | `invalidResponse` | 已覆盖 JSON 解码失败；未覆盖可解码但协议/结构不合法 |
| 非零退出 | `nonzero.sh` 输出可解码 failure JSON、`exit 1`（`:39-51`） | `invalidResponse` | 已覆盖退出状态优先于响应解码（客户端 `:127-129`）；没有独立 `launchFailed` 覆盖 |
| 响应过大 | `oversized-response.sh` 执行 `head -c 300000 /dev/zero`（`:53-60`） | `responseTooLarge` | 已覆盖 256,000 bytes 上限（协议 `PluginRuntimeProtocol.swift:3-11`，客户端检查 `PluginRunnerClient.swift:131-135`）；当前是在进程退出后读文件，不是流式上限 |
| 超时 | `sleep.sh` 执行 `/bin/sleep 2`，客户端 timeout 25ms（验证 `:62-72`） | `timedOut` | 已覆盖超时终止与等待回收（客户端 `:117-123`） |
| 取消 | 同一 `sleep.sh`，timeout 3s；40ms 后取消 Task（验证 `:74-92`） | 捕获 `CancellationError`，总耗时 `< 1s` | 已覆盖取消处理器终止进程（客户端 `:45-54`、`PluginProcessCancellation.cancel:191-201`）；没有带输出流压力的取消回归 |
| 请求过大 | `script` 重复 `x` 1,500,000 次后调用 `invalid` runner（验证 `:94-98`） | `requestTooLarge` | 已覆盖请求上限守卫（客户端 `:64-69`）；这是编码后必然超过上限的粗粒度测试，没有“刚好上限/刚超过”边界，也不启动 fake |

### 已知缺口

- `PluginRunnerClientError.launchFailed` 在 `PluginRunnerClient.swift:13-16` 声明，`process.run()` 失败时在 `:106-110` 映射，但验证文件没有构造“可执行但无法启动”的 fake，因此未覆盖。
- 没有成功响应基线。当前 fake 只有错误脚本；因此 Pipe 改动后，stdin 关闭、stdout 正常收集等成功语义没有直接断言。
- `invalidResponse` 只有空/坏 JSON 以及非零退出；客户端实际还检查 `protocolVersion` 和 `status` 与 `output/error` 的结构一致性（`:136-140`、`isStructurallyValid:154-161`），这些分支未覆盖。
- 客户端当前创建并删除 `ClipAllPluginRunner-<UUID>` 临时目录（`:71-77`），把 request 写入 `stdin.json`、把三条流接到文件（`:79-99`），退出后才读取 stdout（`:131-132`）。现有验证的 `root` 目录（`:15-21`）是 fake 脚本容器，不能证明客户端通信期间没有额外临时目录。
- 当前验证没有检查 stderr。文档虽规定 runner 通过 stdin/stdout 交换单个 JSON（`Docs/PluginSDK/runtime-v1.md:63-67`），stderr 在客户端现状中仍被重定向到文件（客户端 `:81-99`），所以“大 stderr 管道填满”未被覆盖。

## Pipe 迁移必须新增的回归

| 回归 | fake runner 设计 | 期望结果 / 失败信号 | 为什么必须有 |
| --- | --- | --- | --- |
| 不创建临时目录 | fake 在进程存活期间扫描 `${TMPDIR:-/tmp}` 下名称前缀 `ClipAllPluginRunner-` 的目录，并把是否发现写入一个**合法成功响应**（例如 item value 为 `present`/`absent`）。测试断言 `absent`；不要只在 execute 返回后比较目录，因为旧实现会在 `defer` 中删除（客户端 `:71-77`）。 | 成功且 marker=`absent`；marker=`present` 表示旧的文件传输路径仍存在。 | 直接覆盖目标“不落盘”；扫描必须发生在 fake 运行期间，才能捕捉瞬时目录。测试自身的 `ClipAll-RunnerClient-<UUID>` 根目录（验证 `:15-21`）应排除。 |
| 大 stdout + 大 stderr 不死锁 | fake 并发写入 stdout 和 stderr（例如后台 `head -c 300000 /dev/zero >&2`，前台 `head -c 300000 /dev/zero`，最后 `wait`）。客户端 timeout 可设为数秒，避免把“无死锁”误判成默认 750ms 超时。 | 应在有限时间内返回 `responseTooLarge`，而不是挂死/`timedOut`；进程应被回收。若只读 stdout、未排空 stderr，子进程会在管道容量耗尽处阻塞。 | Pipe 的 stdout/stderr 都有有限缓冲；旧实现写文件不会遇到该阻塞。该测试同时验证并发排空和超限处理。 |
| 关闭 stdin 产生 EOF | fake 执行 `cat >/dev/null`（必须读到 EOF）后输出合法成功 JSON。客户端写完 request 后若未关闭 `Pipe` 写端，fake 会一直等待。 | 成功返回合法 response；不应超时。可给该用例短 timeout（如 250ms）使未关闭 stdin 快速失败。 | 当前文件-backed stdin 天然以文件末尾作为 EOF；改成 Pipe 后必须显式关闭写端。仓库已有同类正确顺序可参考 `Verification/PluginRuntimeVerification.swift:95-99`（写 request、关闭 stdin、再读 stdout）。 |

建议另加一个轻量成功用例：fake 输出合法小 JSON、stderr 写入少量文本，断言 `PluginRunnerExecution.response`，作为上述 EOF/正常收集的基线。若大 stderr 用例只与大 stdout 合并并最终返回 `responseTooLarge`，它不能单独证明“正常响应 + 大 stderr”路径已排空。

Pipe 实现仍应让现有取消用例在有输出时成立：取消 handler 必须终止进程并解除 stdout/stderr 读取，否则读取任务可能把取消变成等待超时。现有取消锚点为验证文件 `:74-92`。

## 最小测试改动位置

1. **唯一需要新增测试代码的文件：**
   `Verification/PluginRunnerClientVerification.swift`。
   - 在现有 fake 构造区（`executable(in:name:contents:)`，`:105-123`）旁增加合法成功响应字符串/脚本 helper。
   - 在现有 oversized/sleeper 用例附近（`:53-72`）加入上述三个用例；所有用例复用 `root`、`request()`、`expectClientError`/`expect`（`:101-141`），不需要新 fixture 文件。
   - “不创建临时目录”用例必须在 fake runner 运行期间检查，而不是只检查 `execute` 前后；“EOF”用例应检查成功 response，而不是只检查没有抛错。
2. **验证脚本无需改动：** `Scripts/verify-runner-client.sh:23-38` 已同时编译 `PluginRunnerClient.swift` 和该 Verification 文件并运行产物；`Scripts/verify-all.sh:6-18` 已列出 `verify-runner-client.sh`。
3. **不要把 `Plugins/Examples/TimestampTools.clipallplugin/Tests/cases.json` 当作通信回归 fixture：** 它由 `Verification/PluginRuntimeVerification.swift:50-80` 驱动，覆盖的是时间工具业务结果（当前 15 cases），不是宿主客户端的 Pipe/超时/取消/大小语义。该 verifier 自己已使用 Pipe 并在 `:96-97` 关闭 stdin，但没有 stderr 压力或临时目录断言。

## 与产品实现的对应锚点（供主代理修改时核对）

- 需替换的落盘通信区：`ClipAll/PluginHost/Runtime/PluginRunnerClient.swift:71-99`。
- 当前“等进程退出再读 stdout”的顺序：`:117-135`；Pipe 方案必须在等待终止的同时持续排空 stdout 和 stderr，并在写完 request 后关闭 stdin。
- 保持错误语义的检查顺序：缺失/请求过大 `:60-69`，启动失败 `:106-110`，超时 `:117-123`，取消 `:124-125`，非零退出 `:127-129`，响应大小与结构 `:131-140`。
