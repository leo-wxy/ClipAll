# 外置插件 Runner 无落盘通信

## Goal

让外置插件执行的 request、response 与进程 stderr 全程只经过内存和匿名管道，不创建传输临时目录或文件，使实现重新满足“选中文字不落盘”的产品隐私承诺，同时保持现有插件协议和运行行为兼容。

## Background

- `README.md:90` 和 `Docs/Architecture.md:101` 已明确声明选中文字只存在于当前 `SelectionContext` 与一次 runner request，不落盘。
- 当前 `PluginRunnerClient.executeSynchronously` 会在系统临时目录创建 `ClipAllPluginRunner-<UUID>`，把完整 request 写入 `stdin.json`，并创建 `stdout.json`、`stderr.log`；正常结束后才通过 `defer` 删除（`ClipAll/PluginHost/Runtime/PluginRunnerClient.swift:71-88`）。
- request 包含脚本、选中文字、非敏感插件配置、locale/timezone 与日志开关。临时文件行为与现有隐私承诺冲突。
- Runner 已通过 stdin/stdout 交换单个 JSON，传输载体由文件改为匿名 `Pipe` 不需要修改 DTO、JSON 字段、manifest schema 或 `protocolVersion`。

## Key Decision

- 用户明确要求直接完成长期正确的无落盘实现，不接受以收紧临时文件权限、增加残留清理任务或降低隐私文档承诺作为过渡方案或最终方案。

## Requirements

### R1. 无落盘传输

- `PluginRunnerClient` 必须使用匿名内存管道承载 stdin、stdout 和 stderr。
- 执行路径不得为 request、response 或 stderr 创建临时目录、临时文件或其他持久化副本。
- 插件安装包、receipt、开发引用、UserDefaults 与 Keychain 等既有合法持久化不在本要求范围内。

### R2. 协议与错误兼容

- 保持单个 stdin JSON request / stdout JSON response、`protocolVersion: 1` 和现有 DTO 字段不变。
- 保持 request 1,500,000 bytes、response 256,000 bytes、selection 65,536 bytes 等现有限制不变。
- 保持 `runnerMissing`、`requestTooLarge`、`launchFailed`、`timedOut`、`responseTooLarge`、`invalidResponse` 与 `CancellationError` 的可观察语义和判断优先级。
- stderr 只排空并丢弃，不拼接进 stdout，不暴露为调试日志，也不改变 `PluginRuntimeResponse.logs`。

### R3. 管道生命周期与可靠性

- 写完 request 后必须关闭宿主 stdin 写端，让 Runner 的 `readDataToEndOfFile()` 收到 EOF。
- stdout 与 stderr 必须在进程运行期间并发排空，不能等进程退出后再读取。
- stdout 超过上限后仍要继续排空，但内存只保留上限加一个字节或等价的超限标记，避免无界内存增长和子进程背压死锁。
- 保持默认 750 ms timeout、Task cancellation、terminate/SIGKILL fallback 与现有 150 ms 终止收尾窗口。
- 子进程提前退出、EPIPE 或异常继承 pipe FD 时，I/O worker 不能让调用永久阻塞，也不能覆盖已经确定的公开错误。

### R4. 日志与调试兼容

- 正式能力执行 `capturesLogs: false` 时继续丢弃 JS 内存日志。
- 开发者调试 `capturesLogs: true` 时继续通过 JSON response 返回截断后的本次 session 日志。
- 不新增日志采集、日志持久化或 stderr UI 展示。

### R5. 回归验证

- 保留现有 Runner client 错误、超时、取消和大小限制验证。
- 新增合法成功响应基线，验证 stdin EOF 与 stdout JSON 收集。
- 新增大 stdout 与大 stderr 并发输出验证，确认不死锁并返回 `responseTooLarge`，而不是 `timedOut`。
- 新增执行期间的临时目录监测，确认没有新建 `ClipAllPluginRunner-*` 传输目录；监测应使用执行前基线，避免旧残留导致误报。
- 运行 Runner client 定向验证、插件 runtime 验证、全量 `verify-all.sh` 与 `swift test`。

### R6. 文档同步

- 在 `Docs/PluginSDK/runtime-v1.md` 明确 stdin/stdout 由宿主使用匿名内存管道连接，传输不创建临时文件，stderr 不属于运行协议或调试日志。
- 保留 README 与 Architecture 现有“不落盘”承诺，不通过降低文档承诺来规避实现问题。

## Acceptance Criteria

- [x] AC1：`PluginRunnerClient` 不再引用 `FileManager.default.temporaryDirectory`，不创建或读写 `stdin.json`、`stdout.json`、`stderr.log`。
- [x] AC2：request 写入匿名 stdin pipe 后主动关闭写端；等待 EOF 的合法 fake runner 能在 timeout 内成功返回结构化 response。
- [x] AC3：stdout 和 stderr 在进程运行期间并发排空；同时输出超过 pipe 缓冲区的数据不会死锁，正常退出且 stdout 超限时返回 `responseTooLarge`。
- [x] AC4：stdout 采集有界；超限后继续排空但不会按输出量无限增长内存。
- [x] AC5：现有 missing、invalid、nonzero、oversize、timeout、cancel、request-too-large 验证继续通过，错误类型不变。
- [x] AC6：取消仍在 1 秒内终止 runner；timeout 仍执行 terminate/SIGKILL fallback，I/O worker 不遗留或无限等待。
- [x] AC7：执行期间相对基线没有新增 `ClipAllPluginRunner-*` 临时目录。
- [x] AC8：正式执行与调试执行的 `capturesLogs`、response logs、duration 和错误映射保持不变。
- [x] AC9：`Docs/PluginSDK/runtime-v1.md` 已明确内存管道和 stderr 边界，协议版本及 schema 未改变。
- [x] AC10：`Scripts/verify-runner-client.sh`、`Scripts/verify-plugin.sh`、`Scripts/verify-all.sh` 与 `swift test --disable-sandbox --build-system native` 全部通过。

## Out of Scope

- 不修改 `PluginRuntimeRequest`、`PluginRuntimeResponse`、`PluginRuntimeLimits`、`protocolVersion` 或 manifest schema。
- 不修改外置插件权限模型、App Sandbox、插件签名或进程组隔离。
- 不修改插件安装、配置、Keychain、AI 翻译或 Accessibility 数据链路。
- 不把 stderr 变成产品日志、调试日志或上传数据。
- 不顺手补齐与本隐私修复无关的 `launchFailed`、协议结构分支或 UI 测试缺口。
