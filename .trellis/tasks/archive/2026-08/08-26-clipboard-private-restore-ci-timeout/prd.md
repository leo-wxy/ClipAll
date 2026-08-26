# 修复私有剪贴板恢复 CI 超时

## Goal

消除真实 `NSPasteboard` 私有类型恢复验证在 GitHub CI 上因测试预算过短产生的偶发
`timedOut`，同时保持生产剪贴板事务的 650ms 硬 deadline 不变。

## Confirmed Facts

- 失败场景位于 `Verification/OverlayStateVerification.swift` 的私有类型恢复验证，使用真实
  命名 `NSPasteboard`，当前事务超时为 100ms。
- `ClipboardSelectionFallback` 的严格模式包含 20ms 稳定等待，并从 `042ff83` 起把所有
  轮询与稳定等待严格截断在事务 deadline 内。
- 同一版本在真实 macOS pasteboard 环境连续运行 50 次均通过，CI 报错为该场景
  `timedOut`，符合 Runner 调度偶发耗尽 100ms 测试预算的表现。

## Requirements

- 私有类型恢复验证使用与生产默认事务一致的 650ms timeout。
- 不修改生产 `ClipboardSelectionFallback` 的 deadline、稳定窗口或恢复逻辑。
- 规范明确：依赖真实系统 pasteboard 调度的验证不得使用短于生产事务预算的超时。

## Acceptance Criteria

- [x] `Scripts/verify-overlay-state.sh` 在真实 macOS pasteboard 环境连续运行 50 次通过。
- [x] `Scripts/verify-all.sh` 通过。
- [x] `git diff --check` 通过。
- [x] 生产代码无改动，diff 仅包含验证预算、对应规范和本 Trellis phase。
- [x] GitHub Actions CI run `32925426757` 在提交 `277288d` 上通过。

## Out of Scope

- 放宽或移除生产 650ms 硬 deadline。
- 引入 fake clock、重构剪贴板抽象或修改私有类型恢复实现。
- 修改 README；用户可见行为没有变化。

## Notes

- 这是 `08-25-clipboard-fallback-layered-policy` 的 PRD-only CI 跟进任务。
