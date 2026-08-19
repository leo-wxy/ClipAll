# Runner 内存传输：隐私契约与影响面

## 结论

- 目标是修正 `PluginRunnerClient` 的传输实现，不是扩展插件权限或改变插件合同。现有隐私文档已经声明选中文字不落盘；当前实现只在 Runner 调用期间把 request、stdout 和 stderr 写入临时文件，因此实现与文档契约不一致。
- 保持单次 stdin/stdout JSON request/response、`protocolVersion: 1`、超时/取消/大小限制、`PluginRuntimeResponse.logs` 及错误映射，不需要修改协议 DTO、`manifest-v1` JSON Schema 或插件示例。
- 最小同步面是：`PluginRunnerClient.swift` 的传输端点改为内存管道，并在 `verify-runner-client` 增加/保留对内存传输、超时、取消、响应上限和非零退出的验证；`Docs/PluginSDK/runtime-v1.md` 可补充“传输不创建临时文件”的明确文字。README/Architecture 的“不落盘”声明无需改写，修复后才与实现重新一致。

## 已验证的隐私契约

### 产品与架构文档

- `README.md:88-94` 的“隐私与安全”明确写明“选中文字不落盘”（`README.md:90`）；外置插件运行在独立短进程 JavaScriptCore，且无宿主文件、网络、剪贴板、Accessibility、Shell 或原生对象访问（`README.md:93`）。
- `Docs/Architecture.md:95-101` 的数据所有权把插件安装文件限定在 `PluginInstallationStore` 管理的 Application Support 目录（`Docs/Architecture.md:100`），同时明确“选中文字：只存在于当前 `SelectionContext` 与一次 runner request，不落盘”（`Docs/Architecture.md:101`）。这里的“不落盘”针对选中文字/request 生命周期，不否认插件包、receipt、配置等宿主管理文件的正常持久化。
- `Docs/Architecture.md:53-57` 规定 `PluginHost` 通过 JSON 调用 runner、不把宿主服务对象传给脚本（`Docs/Architecture.md:55`），Runner 不读取插件目录（`Docs/Architecture.md:56`）。
- `Docs/PluginSDK/README.md:62-68` 的 v1 安全边界规定 JS 在独立短生命周期 runner 执行、没有文件/网络/剪贴板/Accessibility/shell/自动化/原生桥接（`Docs/PluginSDK/README.md:64-68`），每次执行新 context 且受超时、输入、输出和日志上限约束（`Docs/PluginSDK/README.md:66`）。

### Runtime 与调试日志语义

- `Docs/PluginSDK/runtime-v1.md:26-28` 明确插件拿不到文件路径或宿主服务对象；`inputMatchers` 只在宿主路由阶段评估，不进入 runner。
- `Docs/PluginSDK/runtime-v1.md:63-67` 把进程协议定义为“stdin/stdout 交换单个 JSON request/response”，顶层含 `protocolVersion: 1`（`Docs/PluginSDK/runtime-v1.md:65`）；每次执行新 runner/context，默认 750ms，超时、取消、非零退出、stdout 污染、无效 JSON、超限响应都应成为当前插件执行错误（`Docs/PluginSDK/runtime-v1.md:67`）。改为 `Pipe` 仍满足相同 stdin/stdout 语义，不需要换协议或加 framing。
- `Docs/PluginSDK/runtime-v1.md:69-71` 规定 `console.log/warn/error` 是纯 JavaScript 内存日志；正式执行丢弃日志，调试器显示截断的本次 session 日志，且日志不得写入选中文字、配置值或结果正文（`Docs/PluginSDK/runtime-v1.md:71`）。
- `Docs/PluginSDK/debugging.md:5-10` 要求调试器检查结果、耗时、错误 code 和 session 日志；`Docs/PluginSDK/debugging.md:53-60` 要求日志不含用户正文、结果正文或配置值。传输端点替换不应改变调试器 `capturesLogs=true` 下返回的 `response.logs`。

## 当前实现与隐私契约的偏差

### 生产调用路径

- `ClipAll/PluginHost/Runtime/PluginRunnerClient.swift:64-69` 先 JSON 编码完整 `PluginRuntimeRequest`（包含脚本、handler、选中文字、配置、locale/timezone 和 `capturesLogs`），再按 `maximumRequestBytes` 检查。
- `ClipAll/PluginHost/Runtime/PluginRunnerClient.swift:71-88` 创建 `FileManager.default.temporaryDirectory/ClipAllPluginRunner-<UUID>`，将 request 写为 `stdin.json`，创建 `stdout.json` 与 `stderr.log`，再打开这些文件作为 Process 的标准输入/输出/错误。这是选中文字及同一 request/response 生命周期中的实际磁盘写入；`defer` 在结束时尝试删目录（`PluginRunnerClient.swift:77`），只能降低残留，不等于“不落盘”。
- `ClipAll/PluginHost/Runtime/PluginRunnerClient.swift:95-100` 把上述文件句柄接到 `standardInput`/`standardOutput`/`standardError`；`PluginRunner` 成功/失败响应最终会写入 stdout（`ClipAllPluginRunner/main.swift:4-20`），客户端结束后 `PluginRunnerClient.swift:131-140` 同步并从 `stdout.json` 读回、做响应大小/协议/结构检查。
- `stderr.log` 当前从未被读取或放入 `PluginRuntimeResponse.logs`；`PluginRunnerClient` 的日志语义实际来自 JSON response 的 `logs` 字段，而不是进程 stderr。若改用管道，应继续丢弃 stderr 或有界读取，避免把 stderr 误暴露为调试 session 日志。

### Runner/JS 侧未发现额外落盘

- `ClipAllPluginRunner/main.swift:4-20` 只从 `FileHandle.standardInput` 读完整 request、通过 `standardOutput` 写完整 response；没有创建文件或读取插件目录。
- `ClipAllPluginRunner/JavaScriptPluginRuntime.swift:18-83` 每次创建新 `JSContext`，把 input 转成内存 JSON 对象，执行脚本并返回结构化 response；`logs(from:enabled:)`（`JavaScriptPluginRuntime.swift:116-125`）只读取内存数组并做数量/长度截断。
- bootstrap 的 `console`（`JavaScriptPluginRuntime.swift:160-193`）把日志放在 JS 内存数组，不访问宿主文件/服务。

## `PluginRunnerClient` 全部调用点与影响

| 调用点 | 证据 | 语义 | 影响判断 |
|---|---|---|---|
| App 装配 | `ClipAll/App/AppEnvironment.swift:30-58` | 创建一个共享 `PluginRunnerClient`，注入生命周期控制器 | 构造签名不需变；只需替换 client 内部 IO |
| 正式外置能力 | `ClipAll/PluginHost/Runtime/ExternalPluginExecutor.swift:45-67` | 构造 `PluginRuntimeRequest`，`capturesLogs: false`（`ExternalPluginExecutor.swift:50-60`），调用 `runnerClient.execute` | 保持错误映射和不返回正式日志；无 DTO 变化 |
| 生命周期/Executor 工厂 | `ClipAll/PluginHost/Lifecycle/PluginLifecycleController.swift:47-76,405-425` | 保存并转发同一 client 到 executor factory 与调试 session | 无持久化或协议影响 |
| 开发调试单次执行 | `ClipAll/PluginHost/Development/PluginDebugSession.swift:79-110,149-166` | `capturesLogs: true`，将 response.output/error/logs/duration 回填 UI | 必须保持 response.logs 与耗时/错误行为；内存 Pipe 不改变 UI contract |
| 开发 fixtures | `PluginDebugSession.swift:112-147` | 循环复用 client 执行 fixture，逐项校验 response | 保持每次新 process/context 与现有顺序、错误码 |
| client 直接验收 | `Verification/PluginRunnerClientVerification.swift:24-98` | 覆盖 missing/invalid/nonzero/oversized/timeout/cancel/requestTooLarge | 应继续覆盖这些错误；可新增成功响应和无临时文件行为断言 |
| 端到端 runner 验收（绕过 client） | `Verification/PluginRuntimeVerification.swift:83-104` | 已使用 `Process` + `Pipe` 的 stdin/stdout/stderr 执行 runner | 该路径本来就是内存传输，可作为目标实现参考；只验证 runner 协议/fixtures |

## 协议 DTO、JSON Schema 与文档同步判断

### 不需要改的合同

- `ClipAllPluginProtocol/PluginRuntimeProtocol.swift:3-12` 只定义协议版本和 request/response/log/result 限制；`PluginRuntimeRequest` 的字段与初始化器在 `:67-90`，`PluginRuntimeResponse` 在 `:148-175`。内存 Pipe 只替换 `FileHandle` 的承载方式，不改变任何字段、编码或限制。
- 仓库唯一机器可读 JSON Schema 是 `PluginSDK/Schemas/plugin-manifest-v1.schema.json`（`Docs/PluginSDK/manifest-v1.md:1-3`）；它描述 `plugin.json` manifest 字段，未描述 runner transport。不存在需要同步的 runtime JSON Schema。
- `Docs/Architecture.md:103-106` 的“修改 manifest 或 runner JSON 字段时同步 DTO、JSON Schema、SDK 文档、示例和兼容测试”仅在字段/语义变更时触发。本任务不改字段或 `protocolVersion`，因此不应提升 manifest/protocol version，也不应改 manifest schema、示例插件或 fixtures 格式。

### 建议的最小文档同步

- 建议在 `Docs/PluginSDK/runtime-v1.md:63-67` 的进程协议段补一句：stdin/stdout 由宿主通过内存管道连接，request/response 不创建临时文件；stderr 不属于协议和调试日志。这样把已有“不落盘”承诺与实现细节对齐。
- `README.md:88-94` 与 `Docs/Architecture.md:95-101` 已准确表达目标契约，改完实现后无需内容调整；若需要变更，只应补充“runner transport 不产生临时文件”，不要扩大为“插件包/配置/receipt 不落盘”。
- `Docs/PluginSDK/debugging.md:5-10,53-60` 的日志检查要求仍有效；无需改日志字段或错误 code。只有当实现选择把 stderr 暴露给 UI 时才会构成语义变更，但当前契约不支持该行为，推荐不要这么做。

## 验证、CI、构建和发布影响

- `Scripts/verify-runner-client.sh:12-38` 编译 `PluginRuntimeProtocol.swift`、`PluginRunnerClient.swift` 和 `Verification/PluginRunnerClientVerification.swift`，然后运行 client 验收；client 实现或其测试变更会由该脚本直接覆盖。
- `Scripts/verify-all.sh:8-24` 将 `verify-runner-client.sh` 纳入完整套件；`.github/workflows/ci.yml:17-36` 在 macOS 15 上运行 `verify-all.sh`、XCTest smoke 和 `Scripts/build-local-app.sh`。无需新增 CI job。
- `Scripts/build-local-app.sh:31-61,92-105` 编译并把 `ClipAllPluginRunner` 嵌入 App，再签名/验签。改变 client IO 不影响 bundle 路径、签名、manifest 或示例资源；重新构建即可把新 client/runner 带入 App。
- `Scripts/verify-plugin.sh:15-36` 构建 Runner 并运行 `Verification/PluginRuntimeVerification.swift`；该验证自身已经使用 `Pipe`（`Verification/PluginRuntimeVerification.swift:87-104`），因此无需协议侧改造。
- `Verification/PluginRunnerClientVerification.swift:17-22,118-129` 的临时目录和脚本文件仅用于构造 missing/invalid/nonzero/oversized/sleep 测试 runner，不是生产 request/stdout/stderr；不能据此把测试 fixture 临时文件误判为产品隐私回归。若验收标准要求“client 不创建 `ClipAllPluginRunner-*` 目录”，可在该测试中加入临时目录快照/探针，但应避免把测试脚本目录与产品传输目录混淆。

## In-scope / Out-of-scope

### In-scope

1. `ClipAll/PluginHost/Runtime/PluginRunnerClient.swift`：将 request 写入 `Pipe`/内存 FileHandle，将 stdout 读取改为 Pipe，stderr 改为丢弃或有界内存管道并确保不会阻塞；保留现有进程生命周期、取消、超时、非零退出、响应上限、JSON decode 与结构校验。
2. `Verification/PluginRunnerClientVerification.swift` 与必要的 `Scripts/verify-runner-client.sh`：验证内存传输仍覆盖现有错误语义，最好增加成功响应/大 stderr 或无临时文件回归断言。
3. `Docs/PluginSDK/runtime-v1.md`：可选地明确 transport 使用内存管道、无临时文件；保留 stdin/stdout JSON、日志和错误原文语义。

### Out-of-scope

- 不改 `PluginRuntimeRequest`、`PluginRuntimeResponse`、`PluginRuntimeLimits`、`capturesLogs`、`protocolVersion` 或任何 JSON 字段。
- 不改 `PluginSDK/Schemas/plugin-manifest-v1.schema.json`、`manifestVersion`、`minimumClipAllVersion`、示例 `TimestampTools`、manifest/fixture 格式。
- 不改插件安装、staging、receipt、Application Support、开发引用源码、配置持久化或 Keychain；这些是明确属于宿主管理文件的持久化边界。
- 不改 AI 翻译 HTTPS 请求边界、Accessibility 取词、剪贴板、系统日志策略或正式插件结果 UI。
- 不把 stderr 变成调试日志或响应字段；不新增日志收集/上传能力。

## 待实现时重点核对的风险

- 用 `Pipe` 时必须在进程退出前/后正确关闭写端并读取输出，避免 stdout/stderr 管道因未消费而阻塞；至少保留当前 750ms timeout 和 cancellation kill 路径。
- stdout 仍只能接受一个 JSON response；不要把 stderr 或插件 JS `console` 混入 stdout，否则会违反 `Docs/PluginSDK/runtime-v1.md:65-67` 的协议/错误语义。
- 生产执行 `capturesLogs=false` 必须继续返回空 `logs`；调试执行 `capturesLogs=true` 必须继续返回截断后的内存 JS 日志。日志不得包含选中文字、配置值或结果正文（`Docs/PluginSDK/runtime-v1.md:69-71`; `Docs/PluginSDK/debugging.md:53-60`）。
- 临时文件消除的是 transport 中间数据；插件安装副本、开发源码、manifest、fixtures、receipt 和设置仍可合法落盘。文档措辞应保持这个范围，避免把“不落盘”误读成整个插件系统零文件。
