# 插件可靠性审查问题修复

## Goal

修复 0.0.12 插件可靠性审查确认的剩余缺口，不改变 Runtime v2、manifest、receipt
格式或插件公开接口。

## Requirements

- `PluginInstallationStore.finalize` 在新插件已激活后消费 pending token；operation directory 清理
  失败不得触发可能依赖已部分删除 backup 的 rollback，下一次 Store 操作必须通过 orphan cleanup
  重试清理并保留完整新版本。
- Store 的统一 direct-child 路径检查必须拒绝目标文件或目录自身为符号链接，包括 dangling
  symlink；不能只验证父目录。
- 生命周期验证必须证明 receipt symlink 即使指向合法 receipt 也不会被读取，并且外部目标不变。
- 替换 rollback 必须显式验证旧 version 与 receipt 原始内容恢复。
- 停用内置插件修复成功后必须显式验证 staging 已清理。
- Runner 响应预算测试必须验证日志裁剪不会修改或丢弃合法 output items。
- 不新增文件事务抽象、协议、依赖、持久化字段或公开错误类型。
- 原归档任务保持历史不改写；本跟进任务在用户真实 App 验收前保持 `in_progress`。

## Acceptance Criteria

- [x] finalize 正常路径清空 staging；异常残留在下一次 Store 操作中清理，且不回滚新版本。
- [x] receipt 文件自身为 symlink 时 `validateInstalled` 明确拒绝，外部 receipt 不被修改。
- [x] 替换 rollback 显式恢复旧 fingerprint、version 和 receipt bytes。
- [x] 停用内置插件自动修复后 staging 为空，插件仍保持停用。
- [x] 响应预算压力下 12 个 output items 的 ID、值长度与顺序保持不变。
- [x] `Scripts/check-version.sh`、`Scripts/verify-all.sh` 和 `git diff --check` 通过。
- [x] 使用稳定签名安装并启动 `/Applications/ClipAll.app`。
- [ ] 用户完成真实 App 验收后再 commit/归档。

## Notes

- 这是对 `08-23-plugin-runtime-lifecycle-reliability` 的小范围跟进，采用 PRD-only 轻量流程。
