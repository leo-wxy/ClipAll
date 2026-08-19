# 外置插件 Runner 无落盘通信设计

## 1. Design Summary

只替换 `PluginRunnerClient` 的进程标准流承载方式：由三个临时文件改为 stdin、stdout、stderr 三个匿名 `Pipe`。Runner executable、JSON DTO、协议版本、调用方和 UI contract 均保持不变。

推荐结构：

```text
PluginRuntimeRequest Data
        |
        v
stdin writer worker --close/EOF--> Runner process
                                      |        |
                                      v        v
                            stdout bounded   stderr discard
                               collector        drainer
                                      |
                                      v
                         PluginRuntimeResponse Data
```

## 2. Boundaries

### Changed

- `ClipAll/PluginHost/Runtime/PluginRunnerClient.swift`
- `Verification/PluginRunnerClientVerification.swift`
- `Docs/PluginSDK/runtime-v1.md`

### Unchanged

- `ClipAllPluginRunner/main.swift`
- `ClipAllPluginProtocol/PluginRuntimeProtocol.swift`
- `PluginRuntimeRequest` / `PluginRuntimeResponse`
- manifest schema、示例插件、插件安装与配置持久化
- `ExternalPluginExecutor`、`PluginDebugSession` 的调用签名和行为

## 3. Process And Pipe Lifecycle

1. 启动前完成 runner executable 与 request 大小检查。
2. 创建 `Process` 和三个 `Pipe`，分别绑定标准输入、标准输出和标准错误。
3. 设置 termination handler 并启动进程；启动失败仍映射为 `launchFailed`。
4. 进程启动后关闭宿主不使用的 pipe 端点，避免宿主持有 stdout/stderr 写端导致 EOF 永远不出现。
5. 启动三个独立 I/O worker：
   - stdin writer：写入完整 request；无论成功或 EPIPE 都关闭写端。
   - stdout collector：分块读取，最多保留 `maximumResponseBytes + 1`，超限后继续读取并丢弃直至 EOF。
   - stderr drainer：分块读取并全部丢弃直至 EOF。
6. 主执行线程维持现有 termination semaphore、timeout 与 cancellation 流程。
7. 进程退出、超时或取消后，在有界窗口内回收 I/O worker；需要时关闭宿主 pipe handle 唤醒阻塞 I/O，不能无界等待。
8. 按现有顺序判断取消、退出码、response 大小、JSON、协议版本与结构，最后返回 duration。

## 4. Concurrency Model

- `execute(_:)` 继续在 `Task.detached` 中执行同步 Process 管理，不占用 MainActor。
- Pipe I/O 使用独立的 Dispatch worker，并以私有、加锁、`@unchecked Sendable` 状态对象保存有界 stdout 数据和 worker 完成状态。
- stdout 与 stderr 必须并发读取；stdin 写入也必须独立执行，因为 request 上限 1.5 MB，大于常见匿名管道缓冲区。
- I/O worker 只报告内部完成/超限状态，不直接决定公开错误；公开错误仍由主进程生命周期与现有校验顺序决定。

## 5. Bounded Output Collection

- stdout 每次读取固定大小 chunk。
- 当累计数据未超过上限时追加；跨越上限时只追加到 `limit + 1` 或设置 `exceeded=true`。
- 超限后继续读取并丢弃剩余 stdout，避免 runner 因 pipe 满而无法退出。
- stderr 始终读取并丢弃，不累计正文，避免隐私内容在宿主内存中形成额外副本。
- 进程正常退出且 `exceeded=true` 时返回 `responseTooLarge`；非零退出仍优先返回 `invalidResponse`。

## 6. Cancellation And Timeout

- 保留 `PluginProcessCancellation` 的 attach-before/after cancellation race 处理。
- timeout 仍为默认 750 ms；超时后调用现有 terminate/SIGKILL fallback，并最多等待 150 ms 的 termination 收尾。
- 取消继续抛 `CancellationError`，且不能被 writer EPIPE、reader close error 或非法 response 覆盖。
- I/O worker 回收也必须有界。异常 descendant 持有 pipe FD 时，主流程主动关闭宿主 handle 并按已确定的 timeout/cancellation 错误返回。

## 7. Error Compatibility

判断顺序保持：

```text
runnerMissing
-> requestTooLarge
-> launchFailed
-> timedOut / CancellationError
-> nonzero exit => invalidResponse
-> responseTooLarge
-> empty / invalid JSON / protocol mismatch / structural mismatch => invalidResponse
```

stdin writer 的 EPIPE、stderr 内容或 worker close error 不新增公开错误类型。

## 8. Privacy Contract

- request、response、stderr 不创建磁盘副本。
- JavaScript `console` 继续由 Runner 在内存中捕获，并只通过结构化 response 的 `logs` 字段返回给调试器。
- transport 修复不等于整个插件系统“零文件”：安装包、receipt、开发源码和设置仍按既有所有权合法持久化。

## 9. Verification Design

- 保留现有错误矩阵。
- 合法 fake runner 先读 stdin 到 EOF，再返回成功 response，以验证写端关闭。
- 压力 fake runner 并发写入大 stdout/stderr；期望 `responseTooLarge` 而非 timeout。
- 无落盘测试在 execute 前记录 `ClipAllPluginRunner-*` 目录基线，在 runner 存活期间轮询新增路径；旧实现应失败，新实现应通过。
- 运行定向 Runner client、真实 Runner fixtures、全量 verification 与 XCTest。

## 10. Alternatives Rejected

- **给临时文件加 `0600` 权限和清理任务**：只能降低暴露与残留，仍不满足“不落盘”。
- **进程退出后再读取 Pipe**：stdout/stderr 可能填满缓冲区，让子进程无法退出并最终误报 timeout。
- **把 stderr 合并到 stdout**：会污染单 JSON response 并改变错误合同。
- **把所有 stdout 无界保存在内存**：恶意 runner 可造成无界内存增长。

## 11. Rollback

改动只涉及 client 内部 transport、验证和 SDK 文档。若 Pipe 方案在目标 macOS/Swift 6 下无法可靠收口，回滚这三个文件即可恢复原行为；不得把临时文件实现作为满足隐私承诺的最终方案。
