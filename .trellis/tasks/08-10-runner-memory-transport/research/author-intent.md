# PluginRunnerClient 作者意图追溯

## Result

2026-08-10 使用 `git-ai search --file ClipAll/PluginHost/Runtime/PluginRunnerClient.swift --verbose` 检索两次，均返回没有 AI prompt history。无法确认原作者为什么选择临时文件，也没有可引用的历史产品决策。

## Objective Inference Only

从当前代码只能客观推断：

- 文件承载 stdin 天然提供完整输入和 EOF。
- stdout/stderr 写入普通文件不会受到匿名 pipe 缓冲区背压，因此宿主可以先等待进程退出、再读取 stdout。
- `defer` 尝试关闭句柄并删除临时目录，说明实现期望这些文件短生命周期存在，但这仍不满足“不落盘”。

Pipe 迁移必须保留 EOF、并发排空、大小限制、响应结构校验、错误优先级、timeout、cancellation、SIGKILL fallback 和 duration。以上是代码约束，不应表述为作者原话或历史决策。
