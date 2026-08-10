# 外置插件 Runner 无落盘通信实施计划

## Preconditions

- 用户已审核并批准 `prd.md`、`design.md`、`implement.md` 后，才运行 `task.py start`。
- 实施前加载 `trellis-before-dev`，完整读取本任务 artifacts、research 与 backend/cross-layer 规范。
- 保留用户初始化产生的 `.trellis/.template-hashes.json` 和 `.trellis/tasks/00-join-clipall/`，不得混入本任务提交。

## Step 1. Establish Baseline

- [x] 运行 `Scripts/verify-runner-client.sh`，确认现有错误矩阵基线通过。
- [x] 记录 `PluginRunnerClient.swift` 中临时目录和三个传输文件的静态锚点。

## Step 2. Replace File Transport With Pipes

- [x] 在 `PluginRunnerClient.swift` 内创建 stdin/stdout/stderr `Pipe`，删除临时目录和文件读写。
- [x] 实现独立 stdin writer、stdout bounded collector、stderr drainer。
- [x] 写完 request 后关闭 stdin 写端；进程启动后关闭宿主未使用端点。
- [x] stdout 超限后继续排空，同时把内存采集限制在 `maximumResponseBytes + 1` 或等价状态。
- [x] 为 I/O worker 增加有界回收与安全 close，不改变 timeout/cancellation 的公开结果。
- [x] 保持 response 校验顺序、duration 和 `PluginProcessCancellation` 语义。

## Step 3. Add Regression Coverage

- [x] 在 `Verification/PluginRunnerClientVerification.swift` 增加合法成功/EOF 用例。
- [x] 增加大 stdout + 大 stderr 并发压力用例，断言 `responseTooLarge` 且非 timeout。
- [x] 增加执行期间临时目录基线监测，断言没有新增 `ClipAllPluginRunner-*`。
- [x] 保留并运行现有 missing、invalid、nonzero、oversize、timeout、cancel、request-too-large 用例。
- [x] 不扩大到与隐私迁移无关的测试缺口。

## Step 4. Synchronize SDK Documentation

- [x] 更新 `Docs/PluginSDK/runtime-v1.md` 的进程协议段：匿名内存管道、无传输临时文件、stderr 不属于协议或调试日志。
- [x] 复核 README/Architecture 现有“不落盘”承诺无需降低或改写。

## Step 5. Targeted Validation

- [x] `Scripts/verify-runner-client.sh`
- [x] `Scripts/verify-plugin.sh`
- [x] 静态确认 `PluginRunnerClient.swift` 不再包含 `temporaryDirectory`、`stdin.json`、`stdout.json`、`stderr.log`。
- [x] 重复运行 Runner client verification，检查无悬挂 runner、无新传输目录。

## Step 6. Full Quality Gate

- [x] `Scripts/check-version.sh`
- [x] `Scripts/verify-all.sh`
- [x] `swift test --disable-sandbox --build-system native`，必要时使用项目内 `.swift-module-cache` 环境。
- [x] 加载 `trellis-check` 做完整 spec、PRD、design、实现和跨层一致性检查；发现问题后修复并重跑。

## Step 7. Finish

- [x] 按 `trellis-update-spec` 判断并记录“敏感进程通信禁止文件中转、Pipe 必须并发排空”的项目规范。
- [x] 更新 PRD acceptance checkboxes 和任务记录。
- [x] 提交前区分本任务文件与用户/Trellis 初始化已有 dirty 文件。
- [x] 向用户展示一次性 commit 计划；获得确认后再 commit，不 push。

## Risk And Rollback Points

- Swift 6 Sendable/FileHandle 编译问题：在 Step 2 小步编译，必要时把可变采集状态封装在加锁的 `@unchecked Sendable` 私有对象中。
- Pipe EOF/close 行为：EOF 成功用例是进入全量验证前的硬门槛。
- 输出背压：大 stdout/stderr 用例未通过时不得继续到文档或完成阶段。
- 错误语义漂移：任何现有 verification 错误类型变化都视为回归，优先修实现而不是改断言。
