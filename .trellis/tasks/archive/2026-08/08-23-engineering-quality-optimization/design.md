# 技术设计

## 设计原则

本阶段只做能够从当前调用关系证明安全的删除与复用。每项改动保持现有数据流、对象所有权和用户界面行为，不引入新的公共抽象。

## 1. AppEnvironment 持有关系收束

当前关系：

```text
AppEnvironment
├── selectionMonitor ──strong──> SelectionCaptureService
└── overlayCoordinator ──strong──> SelectionOverlayStore
```

`AppEnvironment.selectionCapture` 与 `AppEnvironment.overlayStore` 是同一对象的第二份无调用引用。删除属性和赋值，保留初始化局部变量；`selectionMonitor` 与 `overlayCoordinator` 仍由 `AppEnvironment` 持有，因此生命周期不变。

不删除 `runnerClient`：它属于本阶段明确排除的插件链路。

## 2. 应用规则归一化

`SettingsStore.normalizedBundleIdentifier` 继续作为唯一规则。`removeSelectionApplication` 和 `sanitizeAutomaticDisplayPolicies` 调用它，不新增 helper，也不改变持久化 key 或 policy raw value。

## 3. UI 死代码与转发层删除

- 删除无调用的 `ClipAllSurfaceModifier`、`clipAllSurface` 和只供它们使用的主题常量。
- 保留仍被使用的颜色、Inset、设置行和按钮组件。
- 将三处 `actionButton(...)` 调用直接替换为 `OverlayActionButton(...)`，删除只转发参数的方法。

这些变更不改变 SwiftUI 状态来源、modifier 顺序或 action closure。

## 4. 质量入口收束

`Scripts/verify-all.sh` 作为唯一聚合入口，在执行项目验证前运行 `zsh -n "$PROJECT_ROOT"/Scripts/*.sh`。CI 和 Release 已调用该脚本，因此不修改 workflow、不重复执行门禁。

`Docs/Development.md` 只展示聚合入口。日志规范直接描述当前 `OSLog.Logger` 实践，不新增 logger wrapper 或静态 lint。

## 明确不做

- 不添加架构扫描器：当前无违规证据。
- 不拆文件或 target：没有行为或维护收益证据。
- 不缓存 SwiftUI 派生数据：没有性能测量，且候选涉及插件展示。
- 不修改纯插件链路或翻译插件别名。

## 兼容与回滚

- 无数据迁移、配置格式或用户界面合同变化。
- 每组修改可以按文件独立回退。
- 若对象生命周期、设置规则或浮窗行为验证失败，只回退对应源码精简，不影响质量文档与脚本语法门禁。
