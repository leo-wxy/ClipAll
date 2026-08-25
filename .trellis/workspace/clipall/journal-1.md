# Journal - clipall (Part 1)

> AI development session journal
> Started: 2026-08-09

---


## Session 1: 跨 App 兼容取词

**Date**: 2026-08-10
**Task**: 跨 App 兼容取词
**Branch**: `main`

### Summary

实现明确手势触发的 AX 优先与剪贴板复制回退，支持按 App 排除，完成自动验证和 Applications 真机验收。

### Git Commits

| Hash | Message |
|------|---------|
| `0659c01` | (see git log) |

### Status

[OK] **Completed**


## Session 2: 修复浮窗关闭与选择误触

**Date**: 2026-08-11
**Task**: 修复浮窗关闭与选择误触
**Branch**: `main`

### Summary

外部能力执行前同步关闭浮窗；按指针意图、AX 命中语义和剪贴板对象类型过滤选择误触；完成 VSCode、DevEco 与 Codex 回归验证。

### Git Commits

| Hash | Message |
|------|---------|
| `4bddbf7` | (see git log) |

### Status

[OK] **Completed**


## Session 3: 修复无 AX App 双击取词

**Date**: 2026-08-11
**Task**: 修复无 AX App 双击取词
**Branch**: `main`

### Summary

基于 POPO 运行日志区分空 AX 命中与明确非文字目标，复用受约束剪贴板回退；完成全量验证、稳定签名安装和跨 App 手测。

### Git Commits

| Hash | Message |
|------|---------|
| `dc4dffc` | (see git log) |

### Status

[OK] **Completed**


## Session 4: 应用入口可见性设置

**Date**: 2026-08-11
**Task**: 应用入口可见性设置
**Branch**: `main`

### Summary

新增 Dock 与菜单栏图标独立开关，持久化设置并保证至少保留一个入口；完成全量验证并安装到 Applications。

### Git Commits

| Hash | Message |
|------|---------|
| `b411990` | (see git log) |

### Status

[OK] **Completed**


## Session 5: 发布 ClipAll 0.0.11 UI 重设计

**Date**: 2026-08-16
**Task**: 发布 ClipAll 0.0.11 UI 重设计
**Branch**: `main`

### Summary

统一全部设置页与取词浮窗设计，移除独立能力中心，增加三态外观，修复关闭最后窗口退出与外观旧值问题，并更新 README、版本和发布说明。

### Git Commits

| Hash | Message |
|------|---------|
| `9cc80d7` | (see git log) |

### Status

[OK] **Completed**


## Session 6: 完成浮窗过滤与应用级取词设置

**Date**: 2026-08-19
**Task**: 完成浮窗过滤与应用级取词设置
**Branch**: `main`

### Summary

完成全局与应用级自动显示策略、设置页收束和文字证据门禁；验证通过并使用稳定签名安装，用户验收后归档 08-13。

### Git Commits

| Hash | Message |
|------|---------|
| `5798a1eef0d134b9e3a695fa915d2b93c9bbf30a` | (see git log) |

### Status

[OK] **Completed**


## Session 7: 验收 Qt 私有剪贴板兼容取词

**Date**: 2026-08-20
**Task**: 验收 Qt 私有剪贴板兼容取词
**Branch**: `main`

### Summary

确认 VSCode 兼容取词可在 Qt 私有图片剪贴板存在时显示浮窗并无损恢复图片，AX 正常 App 与非文字对象过滤保持正确；归档 08-12。

### Git Commits

| Hash | Message |
|------|---------|
| `70c140a541ef857f3f81410127ece2264a1ed4e9` | (see git log) |
| `89d9293691716432ea10f3fa77d2fbb5181a46da` | (see git log) |

### Status

[OK] **Completed**


## Session 8: 非插件质量优化收尾

**Date**: 2026-08-23
**Task**: 非插件质量优化收尾
**Branch**: `main`

### Summary

精简非插件代码，收束日志与验证规范，并完成构建、安装和签名核验。

### Git Commits

| Hash | Message |
|------|---------|
| `e050a1d` | (see git log) |

### Status

[OK] **Completed**


## Session 9: 插件运行与生命周期可靠性修复

**Date**: 2026-08-23
**Task**: 插件运行与生命周期可靠性修复
**Branch**: `main`

### Summary

修复卸载中断恢复、恢复路径边界、Runner 完整响应预算和内置插件禁用状态，并补齐全量构建与回归验证。

### Git Commits

| Hash | Message |
|------|---------|
| `5f39abf` | (see git log) |

### Status

[OK] **Completed**


## Session 10: 修复微信双击取词

**Date**: 2026-08-24
**Task**: 修复微信双击取词
**Branch**: `main`

### Summary

基于实时日志以原生 I-beam 补足 AX 空路径的文字证据，保留图片严格门禁并完成微信验收。

### Git Commits

| Hash | Message |
|------|---------|
| `96e64d3` | (see git log) |

### Status

[OK] **Completed**


## Session 11: 优化剪贴板回退分层策略

**Date**: 2026-08-25
**Task**: 优化剪贴板回退分层策略
**Branch**: `main`

### Summary

按取词策略自动选择 20ms 单阶段或 120ms 多阶段剪贴板事务，保留微信/Qt 兼容并缩小严格路径等待；完成全量验证、稳定签名安装与真实应用验收。

### Git Commits

| Hash | Message |
|------|---------|
| `8e4adc3` | (see git log) |

### Status

[OK] **Completed**
