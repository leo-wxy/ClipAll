# PluginRunnerClient 无落盘 Pipe 传输设计研究

## 结论

推荐把 `PluginRunnerClient.executeSynchronously` 的三个文件句柄替换为三个 `Pipe`：`stdinPipe`、`stdoutPipe`、`stderrPipe`。进程启动后并发执行一个 request 写入任务、一个 stdout 有界采集任务、一个 stderr 纯排空任务；主线程仍用 termination semaphore 维持现有 750 ms 等待和 150 ms kill 后收尾窗口。不能在 `process.run()` 后用当前执行线程同步写入 1.5 MB request，也不能只在进程退出后读取 stdout/stderr：前者可能被 Pipe 缓冲区阻塞，后者会让 runner 因 stdout/stderr 背压死锁。

## 已验证的现状与协议约束

- `PluginRunnerClient` 先 JSON 编码 request，并在写入前检查 `maximumRequestBytes`；超限抛 `.requestTooLarge`（`ClipAll/PluginHost/Runtime/PluginRunnerClient.swift:64-69`）。
- 当前通信目录和三个文件均由 client 创建；request 写入 `stdin.json`，stdout/stderr 分别写 `stdout.json`、`stderr.log`（`PluginRunnerClient.swift:71-84`）。进程的标准流绑定为“stdin 从文件读、stdout/stderr 向文件写”（`PluginRunnerClient.swift:86-99`）。
- 启动后通过 `termination` semaphore 等待，默认 `timeout` 是 750 ms（初始化 `PluginRunnerClient.swift:36-43`；等待与超时处理 `PluginRunnerClient.swift:101-123`）。超时路径调用 `terminate`，随后最多等待 150 ms，再抛 `.timedOut`（`PluginRunnerClient.swift:119-123`）。
- Task cancellation 通过 `PluginProcessCancellation` 共享对象关联已启动的 `Process`；取消时 terminate，进程仍运行则 `SIGKILL`（`PluginRunnerClient.swift:45-54`、`164-203`）。启动后若取消抢先发生，`attach` 返回 false，client 终止进程并抛 `CancellationError`（`PluginRunnerClient.swift:106-115`）。
- 只有进程正常退出（`terminationStatus == 0`）才继续检查 stdout；非零退出统一抛 `.invalidResponse`（`PluginRunnerClient.swift:124-129`）。正常退出后检查 response 字节数，超过 256,000 bytes 抛 `.responseTooLarge`；空数据、JSON 解码失败、协议版本不是 1、status 与 output/error 结构不一致都抛 `.invalidResponse`（`PluginRunnerClient.swift:131-141`）。
- 协议 limits 为：协议版本 1、request 1,500,000 bytes、response 256,000 bytes、selection 65,536 bytes、最多 100 条日志、每条日志最多 500 字符、最多 12 个结果项（`ClipAllPluginProtocol/PluginRuntimeProtocol.swift:3-11`）。
- runner 使用 `FileHandle.standardInput.readDataToEndOfFile()`，因此必须关闭 stdin 写端才能让 runner 进入解码/执行；输入超限在 runner 侧返回 `request_too_large`（`ClipAllPluginRunner/main.swift:4-13`）。runner 最终将编码后的 response 一次写入 stdout（`main.swift:15-20`）。
- JavaScript runtime 自身检查结果编码后的数据不超过 `maximumResponseBytes`，并将 console 日志保存在 JS 内存中（`ClipAllPluginRunner/JavaScriptPluginRuntime.swift:67-82`、`116-125`）；正式执行设置 `capturesLogs: false`（`ClipAll/PluginHost/Runtime/ExternalPluginExecutor.swift:50-61`）。因此 stderr 当前没有被 client 读取或参与错误语义，新的 stderr Pipe 应持续排空但不保留内容。
- SDK 文档明确规定 stdin/stdout 交换单个 JSON，默认期限 750 ms；超时、取消、非零退出、stdout 污染、无效 JSON、超限响应均为当前插件执行错误（`Docs/PluginSDK/runtime-v1.md:63-67`）。

## 可实施的伪代码

以下是结构和顺序要求，具体 Swift 锁/`DispatchGroup` 封装可沿用现有同步函数；伪代码中的 reader 必须在独立执行上下文中运行。

```swift
let stdinPipe = Pipe()
let stdoutPipe = Pipe()
let stderrPipe = Pipe()

process.standardInput = stdinPipe
process.standardOutput = stdoutPipe
process.standardError = stderrPipe
process.terminationHandler = { _ in termination.signal() }
try process.run()
guard cancellation.attach(process) else {
    terminate(process)
    throw CancellationError()
}
defer { cancellation.detach(process) }

// 三个任务都在 process.run() 之后启动：
// 1) request writer：写完 requestData 后无论成功/失败都关闭 stdin 写端。
//    write 错误（尤其是子进程提前退出导致 EPIPE）不应覆盖现有响应/退出码语义。
// 2) stdout reader：循环 read(upToCount: chunk)，只保留前
//    maximumResponseBytes + 1 bytes；超过上限后继续读取并丢弃，直到 EOF，
//    以免子进程因 stdout Pipe 满而阻塞。
// 3) stderr drainer：循环读取并丢弃直到 EOF；stderr 当前没有业务消费者，
//    但不能不读，否则恶意/错误插件可填满 stderr Pipe。
startWriter(stdinPipe.fileHandleForWriting, requestData, writerGroup)
startBoundedReader(stdoutPipe.fileHandleForReading, maximumResponseBytes, stdoutResult, readerGroup)
startDiscardingReader(stderrPipe.fileHandleForReading, stderrGroup)

let timedOut = termination.wait(timeout: .now() + timeoutSeconds) == .timedOut
if timedOut {
    terminate(process)                         // terminate + SIGKILL fallback
    _ = termination.wait(timeout: .now() + 0.15)
    // 关闭/取消仍阻塞的 reader/writer，并在有限窗口内回收其任务；
    // 不要让 descendants 持有的 pipe FD 把 client 永久卡住。
    finishPipeTasks(withBoundedWait: .milliseconds(150))
    throw PluginRunnerClientError.timedOut
}

// 进程已退出；writer 应已关闭 stdin，reader 应看到 EOF。
// 正常路径也必须有有限回收窗口；超出窗口时关闭 read ends，避免孤儿 FD 永久持有。
finishPipeTasks(withBoundedWait: .milliseconds(150))

if cancellation.isCancelled { throw CancellationError() }
guard process.terminationStatus == 0 else {
    throw PluginRunnerClientError.invalidResponse
}
guard stdoutResult.count <= maximumResponseBytes else {
    throw PluginRunnerClientError.responseTooLarge
}
guard !stdoutResult.isEmpty,
      let response = try? JSONDecoder().decode(PluginRuntimeResponse.self, from: stdoutResult),
      response.protocolVersion == PluginRuntimeLimits.protocolVersion,
      isStructurallyValid(response) else {
    throw PluginRunnerClientError.invalidResponse
}
```

实现时 `stdoutResult` 的“超限”状态不能只依赖最终 `Data.count`：reader 至少保留 `limit + 1`（或单独 `exceeded` 标志）后继续排空。否则正好在 `limit` 截断会把超大 response 误判为合法 JSON；也不能因超限立即停止读取，否则子进程可能卡在 stdout 写入，直到 750 ms 超时。

## 背压、死锁和关闭顺序

### request stdin

`maximumRequestBytes` 是 1,500,000 bytes，远大于 macOS 常见匿名 pipe 缓冲区。因此 `process.run()` 前预写，或启动后在唯一执行线程调用阻塞式 `write(contentsOf:)`，都可能在 child 尚未读取时阻塞；后一种还会阻止主线程进入 termination wait。必须先 `process.run()`，再让独立 writer 写入，并在 `defer` 中关闭写端。关闭是协议必需条件，因为 runner 调用 `readDataToEndOfFile()`（`ClipAllPluginRunner/main.swift:4`）。

writer 不应把 EPIPE/提前关闭当作新的公开错误：现有 client 根本没有“stdin 写失败”错误，且已有验证脚本会启动不读取 stdin 即退出的 runner（`Verification/PluginRunnerClientVerification.swift:30-37`）。这类错误应记录为内部状态或忽略，最终仍按进程退出码和 stdout 内容走 `.invalidResponse` 等既有语义。

### stdout

runner 的 response 虽有 256,000-byte 上限，但验证 runner/恶意插件可能输出任意数量字节；Pipe 若无人读取会填满，child 阻塞，termination semaphore 永远等不到自然退出。stdout reader 必须与 writer、主等待并发；达到上限后继续读并丢弃，直到 EOF。最终判断顺序必须保持“先 cancellation、再退出码、再 response 大小、再 JSON/协议/结构”：这是当前 `PluginRunnerClient.swift:124-141` 的可观察错误优先级。

### stderr

当前 stderr 只写入临时文件，之后没有读取，也不影响 response（`PluginRunnerClient.swift:79-93`、`131-141`）。Pipe 版应使用独立 drainer 读取并丢弃（或仅保留极小、明确非业务的诊断上限），否则插件向 stderr 写满缓冲区即可制造同样的死锁。不要把 stderr 内容拼进 stdout，也不要把 stderr 非空映射为 `.invalidResponse`，否则改变 SDK 文档中“stdout 污染”与错误语义的边界。

### 进程结束、超时、取消

建议顺序：`process.run` → 启动三个 I/O 任务 → `cancellation.attach` 检查 → 主线程等待 termination。超时或取消时先调用现有 `terminate`（SIGTERM 后检查 `isRunning`，必要时 SIGKILL），再等待 termination；终止后关闭 stdin 写端并让 reader 通过 EOF/关闭退出。所有 I/O 任务都必须有有限回收窗口；不能无界等待 `readDataToEndOfFile`，因为子进程可能派生 descendant 并继承 pipe FD，导致 parent 退出后仍无 EOF。若回收窗口耗尽，应关闭 pipe read ends、丢弃未完成采集，并按已经确定的 `.timedOut` / `CancellationError` 返回。

现有 cancellation race 要保留：取消发生在 `attach` 前时，`attach` 返回 false 并抛 `CancellationError`；取消发生在等待期间时，即使子进程刚好正常退出，只要 `cancellation.isCancelled` 为真仍抛 `CancellationError`（`PluginRunnerClient.swift:111-125`）。不要让 writer/reader 任务自己决定公开错误，它们只提供 I/O 状态。

## 语义保持矩阵

| 场景 | 必须保留的结果 |
| --- | --- |
| runner URL 不可执行 | `.runnerMissing`，仍在启动前检查（`PluginRunnerClient.swift:60`） |
| request JSON 超过 1,500,000 bytes | `.requestTooLarge`，不启动进程（`64-69`） |
| 启动失败 | `.launchFailed`（`106-110`） |
| cancellation | `CancellationError`；先终止 child，不能等待完整 750 ms |
| 750 ms 内未退出 | `.timedOut`；terminate + SIGKILL fallback，并保留 150 ms 收尾等待 |
| 非零退出 | `.invalidResponse`，即使 stdout 看似合法或超大也不改变优先级 |
| 正常退出且 response > 256,000 bytes | `.responseTooLarge` |
| 正常退出、stdout 空/污染/JSON 无效/协议版本错误/status 结构不一致 | `.invalidResponse` |
| 正常有效 response | 返回 `PluginRunnerExecution`，duration 从进程启动前的 `startedAt` 计算（现行 `103-104`、`143`） |

## 风险与验证重点

1. Swift `FileHandle` 的 throwing `read(upToCount:)`、`write(contentsOf:)`、`close()` 调用和跨 Dispatch 闭包的 Sendable 约束需在 macOS 15/Swift 6 编译确认；不要使用会在主执行线程同步等待大 request 的 API。
2. 需要专门验证“runner 不读 stdin 即退出”时 writer EPIPE 不会覆盖 `.invalidResponse`；现有 verification 已有 `invalid-response.sh`（`Verification/PluginRunnerClientVerification.swift:30-37`）。
3. 保留现有 oversized stdout 验证（`head -c 300000 /dev/zero`，`Verification/PluginRunnerClientVerification.swift:52-59`），并增加超大 stderr 与超大 stdout 同时输出的 runner，确认不死锁且最终分别得到 `.responseTooLarge`/`.invalidResponse`。
4. 增加 request 接近 1.5 MB 的真实 Pipe 测试，确认 writer 与 runner 并发、stdin 关闭后 runner 能完成；增加 runner 读取 stdin 后延迟响应的 timeout/cancellation 测试。
5. 正常退出与超时/取消都应验证 reader/writer 任务不会遗留；可通过重复执行、进程列表和文件系统检查确认没有 `ClipAllPluginRunner-*` 临时目录/文件被创建。

## 未覆盖/待实现细节

- Foundation Pipe 在“关闭 read end 以唤醒另一线程阻塞读取”上的具体行为需要在目标 macOS 15 实机验证；如果单纯 close 不能可靠唤醒，应改用专用 reader 线程 + `DispatchSourceRead`/可取消句柄，并仍保留有限主流程超时。
- 是否需要记录 stderr 诊断未由现有协议规定；当前行为是写盘但不消费，建议 Pipe 版维持“排空且丢弃”以避免扩大公开 API 或错误语义。
- 子进程派生 descendant 持有 stdout/stderr FD 是异常 runner 行为；若产品需要对此强保证，应考虑进程组级 kill 或在 reader 设计中增加硬关闭策略，但这超出当前 client 的既有 `Process` 单进程终止语义。
