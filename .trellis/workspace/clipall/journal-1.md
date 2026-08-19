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
