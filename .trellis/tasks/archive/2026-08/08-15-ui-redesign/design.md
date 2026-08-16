# 全局 UI 重设计技术设计

## 1. Design Summary

本任务沿用现有 SwiftUI/AppKit 架构，只重排信息归属并替换共享视觉语言：

- 删除独立能力中心；插件是能力的唯一归属入口。
- “操作栏”只展示、排序和取消固定已有能力。
- 设置页继续使用现有五项主导航，不重建导航状态或窗口体系。
- `ClipAllTheme` 统一拥有浅色、深色、状态、材质和阴影语义。
- 浮窗只改 SwiftUI 外观和现有 phase 的视觉映射，不改 Store、Coordinator、
  placement 或执行时序。

```text
CapabilityRegistry + PluginLifecycleController
                    |
                    v
        插件列表（按插件/能力搜索）
                    |
                    v
        所属插件详情：配置 | 能力
                    |
          SettingsStore.setPinned
                    |
          +---------+---------+
          v                   v
  操作栏排序设置        取词浮窗固定操作
```

现有 `CapabilityRegistry`、`PluginLifecycleController` 和 `SettingsStore` 仍是
唯一数据源；不新增 repository、同步层或能力专用 view model。

## 2. Information Architecture

### 2.1 Remove Capability Center Completely

- 从 `ClipAllApp` 删除 `capability-center` `Window`、菜单项和 `⌘⇧K`。
- 删除 `CapabilityCenterView.swift`，不把它重命名或迁移成另一个独立页面。
- 将它有价值的展示能力迁入插件详情：用途、适用内容、示例、来源内的固定状态。
- 更新当前架构文档；历史 Trellis 任务保持原样。

### 2.2 Plugins Own Capabilities

插件页保持“插件集合 + 聚焦详情”的现有结构：

- 集合顶部增加一处上下文搜索，匹配插件名称、摘要、能力名称和用途；搜索结果
  仍然只显示插件行，不生成全局能力结果列表。
- 详情继续保留“配置 / 能力”分段；能力段按当前插件展示能力信息。
- 每个能力行显示名称、用途、适用内容、首个示例和固定状态。固定操作直接调用
  `SettingsStore.setPinned`。
- 达到四项上限时，未固定项的按钮禁用并给出原因；已固定项仍可取消固定。
- 已停用的本地插件仍可展示声明信息，但不得固定其不可执行能力。
- 插件启停、导入、卸载、开发引用、配置和调试行为不变。

### 2.3 Operation Bar Owns Order Only

`CapabilitiesSettingsView` 删除“可固定能力”目录和相关派生列表，仅保留：

- 已固定能力名称、图标与来源插件；
- 上移、下移和取消固定；
- 空状态提示用户在插件详情中固定能力。

页面仍观察 `CapabilityRegistry`，只用于解析已固定 ID 的显示信息，不承担发现职能。

## 3. Visual System

### 3.1 Theme Tokens

`ClipAllTheme` 增补并集中维护以下语义角色：

- `canvas`、`sidebar`、`contentSurface`、`elevatedSurface`、`overlaySurface`；
- `textPrimary`、`textSecondary`、`separator`、`border`；
- `accent`、`accentSoft`、`selectionFill`、`focusRing`、`spark`；
- `success`、`warning`、`error`；
- `shadowElevated`、`shadowFloating`。

颜色使用 appearance-aware `NSColor`：浅色为暖象牙分层、深墨文字和 cobalt blue；
深色为石墨/深蓝分层、冷白文字和同一品牌蓝。现有 `surface` 可作为兼容别名，避免
无关页面一次性改写。功能 View 不再定义品牌色、浮窗底色或局部阴影。

### 3.2 Settings Structure

复用现有 SharedUI 文件建立两个小型、重复使用的布局原语：

- 页面头部：紧凑标题和一句说明；
- 设置 section：标题、说明、行内容和分隔线，不带独立圆角卡片或阴影。

`SelectionSettingsView`、`GeneralSettingsView`、`CapabilitiesSettingsView` 和
`DeveloperSettingsView` 使用同一页面骨架。现有绑定、按钮 action、空状态和控制顺序
原样保留。`SettingsRootView` 保持两列结构，但品牌区不再包成 hero card；导航、集合和
详情通过背景层级、选中边和文字权重区分。

插件页是唯一需要内部 collection/detail 的页面。插件列表保留一层结构表面；详情直接
属于内容平面，配置和能力内部使用分组行与分隔线，不再嵌套多层 card/inset。

`PluginConfigurationForm` 只把现有不一致的 230/250/300/360 点字段宽度收敛为共享、
可伸缩的标签列和控制列；不改字段类型、可见性、持久化或 Keychain 行为。

### 3.3 Interaction And Accessibility

- selected 同时使用蓝色软底/边和较强图标或文字，并保留 `.isSelected`。
- pinned 同时使用 `pin.fill` 或明确文案与 accessibility label，不只依赖蓝色。
- hover、pressed、keyboard focus 和 disabled 使用不同视觉；按压反馈仍立即发生。
- 新增或调整的动画读取 Reduce Motion；透明浮窗读取 Reduce Transparency，并降级为
  更实的 `overlaySurface` 与更清晰边框。
- 系统 warning/error/success 使用集中语义 token；红色不再承担普通强调。

## 4. Selection Overlay Boundary

`SelectionOverlayView` 保留以下不可变合同：

- 固定宽度 324 点，compact 高度 36 点；
- action bar 始终位于最上方，扩展内容只向下增长；
- 按钮顺序、复制/粘贴/执行 closure 和更多入口不变；
- `SelectionOverlayStore`、`SelectionOverlayCoordinator`、`OverlayPlacement` 不改；
- 非激活面板、显式搜索焦点、顶边锚定、Escape/外点关闭和输入保护不变。

视觉只在已有 SwiftUI 层完成：

- 外层使用单层原生 material + `ClipAllTheme.overlaySurface`，统一边框和 floating shadow；
- active capability 从现有 phase 的 capability ID 派生蓝色高亮，不新增状态；
- 按钮与结果保持同一 surface，更多/执行/结果/翻译/错误只增加向下内容；
- Reduce Motion 下取消旋转/缩放等空间反馈，保留短暂颜色或透明度反馈；
- 原文/译文不增加箭头、连接线或方向动效。

推荐行现有的 `arrow.right` 是可点击动作的 affordance，不是原文与译文连接。本任务仅在
视觉复核中确认它不出现在翻译输入/输出之间，不因文案规则误删行为提示。

## 5. File Boundary

### Delete

- `ClipAll/Features/CapabilityCenter/CapabilityCenterView.swift`

### Modify

- `ClipAll/App/ClipAllApp.swift`：删除独立窗口和菜单入口。
- `ClipAll/SharedUI/ClipAllTheme.swift`：语义 token、共享页面/section、交互状态。
- `ClipAll/Features/Settings/SettingsRootView.swift`：品牌区和主内容层级。
- `ClipAll/Features/Settings/SelectionSettingsView.swift`：采用共享平面 section。
- `ClipAll/Features/Settings/GeneralSettingsView.swift`：采用共享平面 section和语义状态色。
- `ClipAll/Features/Settings/CapabilitiesSettingsView.swift`：只保留已固定项管理。
- `ClipAll/Features/Settings/DeveloperSettingsView.swift`：采用共享平面 section和明确关闭态。
- `ClipAll/Features/PluginManagement/PluginsSettingsView.swift`：插件内搜索、能力详情与固定。
- `ClipAll/Features/PluginConfiguration/PluginConfigurationForm.swift`：统一自适应表单列。
- `ClipAll/Features/SelectionOverlay/SelectionOverlayView.swift`：单层浮窗视觉与 active 状态。
- `Docs/Architecture.md`：删除现行能力中心说明。

### Keep Unchanged

- `CapabilityRegistry`、`SettingsStore`、`PluginLifecycleController`、`AppEnvironment`；
- `SelectionOverlayStore`、`SelectionOverlayCoordinator`、`OverlayPlacement`；
- 插件 manifest、Runner、协议、schema、持久化 key 和执行逻辑；
- 用户现有未跟踪文件 `design-qa.md` 和历史任务文档。

## 6. Compatibility And Data Flow

本任务没有 schema 或数据迁移。原有 pinned capability ID 顺序继续由 `SettingsStore`
持久化；插件详情只是新增同一 `setPinned` 入口，操作栏和浮窗继续观察同一数组。

停用、替换或卸载插件时，`PluginLifecycleController` 继续负责注销能力并清理失效固定项；
UI 不复制清理逻辑。插件搜索只读现有 descriptor/package definition，不缓存第二份能力状态。

## 7. Risks And Mitigations

| Risk | Mitigation |
|---|---|
| 全局 theme 影响调试器等非主设置页 | 保留现有 token API，使用语义兼容别名；安装后抽查调试器和 sheets |
| 搜索后当前插件从结果消失 | 继续用现有 ID reconcile 逻辑，选中首个可见插件或空状态 |
| 停用插件仍从安装包显示能力 | 固定按钮根据 managed state 禁用，生命周期仍负责实际注册状态 |
| 四项上限只在 UI 表现 | `SettingsStore.setPinned` 继续是最终约束，UI 只提前解释 disabled 原因 |
| 浮窗材质导致透明度/对比度不足 | Reduce Transparency 使用实色 surface；明暗模式分别真实截图复核 |
| 动画或 layout 改坏输入/锚点 | 不改 Store/Coordinator/Placement；运行现有数字验证并手测焦点/IME |

## 8. Alternatives Rejected

- 将能力中心改名后保留：仍然制造用户已否定的独立概念。
- 新建 capability repository/view model：复制 registry、lifecycle 和 settings 的现有职责。
- 把“操作栏”改成能力目录：再次产生重复归属。
- 重写成新的 `NavigationSplitView` 或第三方设计系统：扩大窗口、状态和依赖风险。
- 为概念图补不存在的新能力、选区圆点或翻译箭头：把视觉参考误当功能需求。
- 修改浮窗 Store/Coordinator 来实现视觉：没有必要，并会威胁焦点与跨 App 输入合同。

## 9. Rollback Shape

视觉 token、设置布局、插件能力展示和浮窗样式可按步骤独立回退；没有持久化迁移需要撤销。
能力中心删除与插件详情补齐应作为同一步提交面处理，避免短暂丢失能力查看/固定入口。若该步
验证失败，整体恢复 scene、菜单和 View 文件，不对用户数据做任何变换。
