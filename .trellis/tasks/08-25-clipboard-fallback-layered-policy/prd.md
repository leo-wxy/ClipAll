# 优化剪贴板回退分层策略

## Goal

按取词意图自动选择快速单阶段或兼容多阶段剪贴板事务，在保留微信、Qt 应用兼容性的同时，缩小统一 120ms 安静窗口对其他应用的影响。

## Confirmed Facts

- 当前热修复让所有剪贴板回退统一等待 120ms 安静窗口；它已解决微信“临时文本 → 文件 URL → 最终图片”的分阶段写入问题。
- 能直接通过 Accessibility 读取选区的应用不进入剪贴板回退，不受该等待影响。
- 微信实测的分阶段写入约在 50ms 内完成。
- 当前已有四种回退意图：`.disabled`、`.textHitRequired`、`.compatiblePointer`、`.enabled`。
- macOS 公共 `NSPasteboard` API 不提供写入者 PID，无法可靠判断后续写入究竟来自源应用还是第三方应用。

## Requirements

- 策略必须是内部自动决策，不新增设置入口、持久化字段、应用白名单或剪贴板类型白名单。
- `.disabled` 不得触发剪贴板回退。
- `.textHitRequired` 使用 `singleWrite`：首个写入后只保留约 20ms 的稳定检查；若随后出现新 generation，保守返回 `clipboardChanged`，不得覆盖外部写入。
- `.compatiblePointer` 使用 `stagedWrite`：每次 change count 变化都重置 120ms 安静窗口，直到稳定后再判断最终内容。
- `.enabled` 使用 `stagedWrite`，只在显式取词且 Accessibility 读取失败后承担额外等待，以保留微信、Qt 等分阶段复制兼容性。
- 复用现有 `SelectionFallbackPolicy` 做穷举映射，不为两种事务行为新增独立模式类型。
- 两种模式都必须保留现有 650ms 总超时、源进程前台校验、任务取消、原剪贴板快照恢复，以及最终化时的精确 change count 守卫。
- 只对稳定后的最终内容进行文本/非文本分类；最终为非文本时恢复原快照，若原剪贴板为空则清空本次复制内容。
- 分类完成到恢复/清理之间若出现新写入，必须保留新内容并返回 `clipboardChanged`。
- 不改变 Accessibility 直接取词、选区几何、浮窗展示或用户可见交互。

## Acceptance Criteria

- [x] 测试覆盖四种 `SelectionFallbackPolicy` 的完整模式映射：`.disabled` 不调用、`.textHitRequired` 单阶段、`.compatiblePointer` 与 `.enabled` 多阶段。
- [x] `singleWrite` 覆盖正常文本，以及首个写入后的第二次 generation；后者返回 `clipboardChanged` 并保留新内容。
- [x] `stagedWrite` 覆盖微信真实顺序：临时文本 → 文件 URL → Qt 图片/TIFF；最终返回 `nonTextContent` 并清理本次图片写入，同时覆盖 Chromium 多格式文字。
- [x] 两种模式复用同一状态机；共享测试覆盖超时、取消、恢复原快照、不安全快照和最终化阶段外部写入，不为模式复制重复用例。
- [x] 两种模式共享内容分类与最终化逻辑，不复制出两套容易漂移的恢复/清理实现。
- [x] 不新增 UI、设置 schema、应用名单或 UTI 特判。
- [x] 定向状态验证、完整验证、App 构建和 `git diff --check` 全部通过。
- [x] 使用稳定的 `ClipAll Local Development` 身份安装后，真实验证微信文本、微信图片、标准 AX 文字，以及快捷键/菜单显式取词。

## Out of Scope

- 使用私有 API、注入或事件窃听推断剪贴板写入者。
- 按 bundle identifier、Qt 版本或剪贴板 flavor 维护兼容名单。
- 新增用户手动选择事务模式的设置。
- 修改 Accessibility 直接取词或选区几何链路。

## Product Decision

- `.enabled`（快捷键/菜单等显式取词）映射到 `stagedWrite`。
- 不提供用户设置，也不按应用分流；策略由触发意图自动决定。
