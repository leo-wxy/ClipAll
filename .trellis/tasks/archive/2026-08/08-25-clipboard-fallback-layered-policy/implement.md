# 实施计划

## 1. 固定策略契约

- 先为四种 `SelectionFallbackPolicy` 添加完整映射验证。
- 固定 `.enabled` 接受分阶段写入的显式期望。
- 让测试在现有统一 120ms 实现下暴露缺失的分层行为。

## 2. 复用现有策略

- 在 `SelectionFallbackPolicy` 上增加穷举属性，`.textHitRequired` 不接受分阶段写入，`.compatiblePointer` 与 `.enabled` 接受，`.disabled` 为 false。
- 修改 `ClipboardSelectionFallback.captureSelection`，要求唯一生产调用方显式传入 `acceptsStagedWrites`，不设置默认值。
- 不新增模式 enum、配置项或应用规则；`.disabled` 保持不调用。

## 3. 分离稳定判定，复用最终化

- `singleWrite`：首写后短暂稳定检查，第二个 generation 保守返回 `clipboardChanged`。
- `stagedWrite`：保留已验收的 120ms 可重置安静窗口。
- 两种模式继续复用现有的内容分类、快照恢复、非文本清理与精确 generation 守卫。
- 删除被新模式替代的统一等待常量或重复分支，不做无关重构。

## 4. 自动验证

- 运行选区/浮窗定向验证，确认新增回归先失败后通过。
- 构建完整 App。
- 运行仓库完整验证脚本。
- 运行 `git diff --check` 并检查最终 diff 只覆盖本 phase。

## 5. 规范与真实应用验收

- 将已验证的模式映射和事务契约更新到前端质量规范。
- 安装前检查稳定的 `ClipAll Local Development` 身份。
- 用项目安装脚本安装，并核验主 App 与 Runner 的签名和 designated requirement 一致。
- 真实验证微信文本、微信图片、TextEdit 文本，以及快捷键/菜单显式取词。
- 只有用户明确验收通过后才提交并归档该 phase。
