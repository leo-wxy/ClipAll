# 浮窗过滤与取词设置设计

## Scope And Boundaries

本任务只增加自动鼠标取词策略和设置 UI，不改变 AX 解析、剪贴板对象过滤、浮窗呈现或能力执行。

```text
鼠标手势
  -> PointerSelectionIntent
  -> 全局/应用策略门禁
  -> AX 捕获
  -> 必要时兼容取词
  -> 固定安全过滤
  -> SelectionContext
  -> 浮窗

快捷键/菜单
  ---------------------------> AX/兼容取词 -> 浮窗
```

策略门禁放在 `SelectionMonitor` 调度捕获之前。这样被禁用的 App 不运行 AX，也不会产生剪贴板副作用；快捷键和菜单继续绕过自动策略。

## Policy Model

### Global Defaults

`SettingsStore` 新增两个默认 `true` 的持久化字段：

- `isDragSelectionEnabled`：控制 `.drag` 与 `.shiftClick`。
- `isMultiClickSelectionEnabled`：控制 `.multiClick`。

### Per-App Display Policy

```swift
enum SelectionAutomaticDisplayPolicy: String, Codable {
    case followGlobal
    case dragOnly
    case disabled
}
```

按 Bundle ID 持久化 `[String: SelectionAutomaticDisplayPolicy]`：

| 策略 | drag / shiftClick | multiClick | hotkey / manual |
|---|---:|---:|---:|
| followGlobal | 跟随全局 | 跟随全局 | 允许 |
| dragOnly | 允许 | 拒绝 | 允许 |
| disabled | 拒绝 | 拒绝 | 允许 |

缺少 Bundle ID 时使用全局规则。未知或损坏的持久化枚举值按 `followGlobal` 处理。

### Compatibility Reuse

不迁移、不删除现有 `selectionFallbackExcludedBundleIdentifiers.v1`：

- 显示规则字典与旧排除集合共同组成 UI 的应用列表。
- 每个应用行可直接切换是否允许兼容取词，内部继续复用 `setSelectionFallbackExcluded`。
- 旧版本已排除的 App 升级后自动出现在同一个应用列表，显示规则为“跟随全局”、兼容取词关闭。
- 删除应用规则时删除显示策略并解除兼容取词排除。

这样无需一次性数据迁移，也不会把原本仅禁用 fallback 的 App 错升级为完全禁用浮窗。

## Decision Order

1. `PointerSelectionGesture` 只识别意图，不读取设置。
2. `SelectionMonitor` 在 mouse-up 后读取当前前台 Bundle ID，并调用注入的策略闭包。
3. 策略拒绝时记录不含正文的 `userPolicy` 日志并使旧浮窗失效，不调用 `SelectionCapturing`。
4. 策略允许时保持现有 45ms settle、AX、hit classifier、兼容取词、去重和浮窗链路；自动拖选与多击统一使用 `textHitRequired`，图片/控件及空 AX 路径在合成 `Command-C` 前拒绝，快捷键与菜单仍可使用完整回退。
5. 快捷键与菜单不调用鼠标策略闭包。

`AppEnvironment` 继续作为唯一装配点，闭包实时读取 `SettingsStore`，设置修改无需重启 monitor。

## Settings UI

侧栏顺序：`取词 / 通用 / 操作栏 / 插件 / 开发者`，首次打开默认选择“取词”。

### 取词页

1. **自动显示**
   - 自动监听文字选择总开关。
   - 拖选文字后显示。
   - 双击/多击文字后显示。
2. **应用规则**
   - 空状态说明。
   - `.app` 选择按钮。
   - 每行显示图标、名称、Bundle ID、三态 Picker、兼容取词开关与移除按钮。
   - 标题旁帮助按钮收束固定安全过滤说明，不单独占用卡片。
3. **高级：兼容取词**
   - 全局复制回退开关与内存恢复说明。

### 通用页

保留全局快捷键、应用入口和辅助功能权限。删除重复的自动监听与兼容取词卡片。

全部复用 `ClipAllSectionCard`、系统 `Toggle`、`Picker`、`NSOpenPanel` 与现有主题；不加动画、弹出式规则编辑器或新设计组件。
规则只从设置页进入；浮窗和菜单栏菜单不增加设置按钮、上下文菜单或引导提示。

## Validation

- 纯策略矩阵验证：全局开关、三态 App 策略、快捷路径边界。
- UserDefaults 验证：默认值、重启持久化、损坏值、旧 fallback 排除兼容、删除规则。
- 捕获链验证：策略拒绝时不调用 capture；允许时现有手势与 fallback policy 不变。
- 非文本预过滤验证：自动拖选、多击的图片命中和空 AX 路径不得进入剪贴板回退；快捷键和菜单主动取词继续使用完整回退。
- 设置 UI 通过 Swift 构建和 `/Applications/ClipAll.app` 人工检查。

## Rollback

回滚新设置键、`SelectionMonitor` 策略闭包、`SelectionSettingsView` 和侧栏入口即可恢复现有行为。旧 fallback 排除键未迁移或删除，不存在数据回滚风险。
