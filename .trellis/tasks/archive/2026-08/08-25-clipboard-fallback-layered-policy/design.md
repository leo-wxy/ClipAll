# 剪贴板回退分层策略设计

## Design Summary

复用现有两层，不新增模式抽象：

1. `SelectionFallbackPolicy` 继续表达调用场景已有的意图与证据，并通过穷举属性说明是否接受分阶段写入。
2. `ClipboardSelectionFallback` 只执行调用方传入的 `acceptsStagedWrites`，不猜应用类型，也不维护名单。

## Proposed API

```swift
extension SelectionFallbackPolicy {
    var acceptsStagedClipboardWrites: Bool { /* exhaustive switch */ }
}

func captureSelection(
    sourceProcessIdentifier: pid_t,
    acceptsStagedWrites: Bool
) async throws -> String
```

参数不提供默认值；唯一生产调用点必须显式传入策略结果。这样不增加只有两个 case 的中间类型，同时保留编译期穷举检查。

## Policy Mapping

| 回退策略 | 剪贴板行为 | 原因 |
| --- | --- | --- |
| `.disabled` | 不调用 | 当前场景不允许剪贴板副作用 |
| `.textHitRequired` | `singleWrite` | 已有文本命中证据，优先低延迟并保守保护后续写入 |
| `.compatiblePointer` | `stagedWrite` | 兼容 Qt/微信等分阶段复制 |
| `.enabled` | `stagedWrite` | 显式取词优先覆盖更多应用，等待仅发生在 AX 失败后 |

## Transaction State Machine

两种模式共享主状态机：

`snapshot → clear → sendCopy → awaitFirstChange → settle → classify → finalize`

### `singleWrite`

- 首次观察到的 change count 必须是 ClipAll 清空后的紧邻 generation；如果首次轮询已经跨过一代，直接按 `clipboardChanged` 处理。
- 观察到首个 change count 后等待约 20ms。
- 期间没有变化：进入最终分类。
- 期间出现第二个 generation：立即按 `clipboardChanged` 处理，不把后续内容归属于本次复制。

### `stagedWrite`

- 观察到首个 change count 后开始 120ms 安静窗口。
- 每次 change count 变化都重置窗口。
- 连续稳定 120ms 后进入最终分类。
- 整个事务仍受 650ms 总超时约束。

两种模式的每次休眠都只等待 deadline 前的剩余时间，650ms 是硬上限而不是下一次轮询前的软检查点。

## Shared Classification and Finalization

- 稳定前不根据临时 flavor 提前判断结果。
- 稳定后读取最终内容：有效文本返回文本；非文本返回 `nonTextContent`。
- 恢复或清空前再次核对精确 change count。
- 若最终化阶段检测到新 generation，保留外部内容并返回 `clipboardChanged`。
- 原剪贴板快照、flavor/UTI 保存方式沿用现有实现，不另造一套序列化逻辑。

## Safety Boundaries

- 发出复制事件前和等待期间保留源进程前台校验。
- 保留任务取消传播，不吞掉取消。
- 日志只记录模式、阶段和错误，不记录剪贴板内容。
- 不使用公共 API 无法提供的写入者身份，不用 bundle identifier 或 UTI 猜应用。
- `stagedWrite` 的固有限制是：安静窗口内真实外部写入仍无法与源应用分阶段写入完美区分；该风险仅保留在明确需要兼容性的路径。

## Verification Design

- 模式映射做穷举测试，避免未来新增策略后默默落入默认值。
- 让测试剪贴板与 AppKit 一致，只在 `clearContents()` 时增加 change count；用生产一致的 20ms 延迟测试 `singleWrite` 的首写成功、首次轮询前二次写入和后续二次写入保护。
- 用临时文本 → 文件 URL → Qt 图片/TIFF 回归序列测试 `stagedWrite`。
- 模式分支各保留一个最小回归；超时、取消、快照恢复与最终化阶段外部写入由共享状态机测试一次，不复制两套用例。
- 最后执行完整脚本、稳定签名安装与真实应用验收。

## Rollback

若分层策略出现回归，可回退模式参数和映射，恢复当前统一 120ms 安静窗口；不涉及数据迁移、设置兼容或持久状态清理。
