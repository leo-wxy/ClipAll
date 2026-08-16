# 全局 UI 重设计实施计划

## Success Standard

安装到 `/Applications/ClipAll.app` 的真实应用在浅色和深色下均符合批准基准：设置页具有
清晰的导航、集合和详情层级，独立能力中心完全消失，能力在所属插件中可查看和固定，
操作栏只管理已固定顺序，取词浮窗保持 324 点和全部输入/锚定契约并采用同源浮动材质。
现有插件、配置、取词和剪贴板行为回归通过，且用户明确验收后才提交或归档。

## Preconditions

- 用户审核 `prd.md`、`design.md` 和本计划后，才运行 `task.py start`。
- 实施前加载 `trellis-before-dev` 和本任务 context manifest。
- 只修改 `design.md` 列出的文件；发现需要改协议、schema、持久化、Coordinator 或 Store 时
  停止并重新评估，不顺手扩范围。
- Ponytail full 持续生效：删除/复用优先，不增加第三方依赖和推测性抽象。
- 保留用户现有未跟踪 `design-qa.md`，不格式化或改写无关代码。

## Step 1. Record Baseline

- [ ] 记录 `git status --short`，确认本任务文件和既有 `design-qa.md` 的边界。
- [ ] 运行 `swift build --target ClipAll` 和 `Scripts/verify-overlay-state.sh`。
- [ ] 运行 `Scripts/verify-all.sh`，记录任何与本任务无关的既有失败。
- [ ] 静态记录能力中心入口、旧红 accent、feature-local overlay colors 和 section card 使用点。

Rollback point：本步不改代码。

## Step 2. Establish The Shared Visual Language

修改 `ClipAll/SharedUI/ClipAllTheme.swift`：

- [ ] 把普通强调色切为 appearance-aware cobalt blue，加入批准的浅色暖象牙与深色
      graphite/navy surface、文字、状态、focus、spark 和 shadow 语义 token。
- [ ] 保留必要的旧 token 兼容别名，避免一次性改写无关 feature。
- [ ] 让 surface/inset/selectable/hover 原语使用语义 token，区分 selected、hover、pressed、
      focus 和 disabled。
- [ ] 将重复的设置页头部和 flat section 收敛为现有 SharedUI 文件内的最小原语；不再让
      每个 section 自带圆角卡片和阴影。
- [ ] 动画读取 Reduce Motion；材质相关样式准备 Reduce Transparency 降级。

定向验证：

```bash
swift build --target ClipAll
rg -n "0\.72|0\.29|0\.23|Color\(red:" ClipAll/SharedUI ClipAll/Features
```

Rollback point：只回退 Theme/SharedUI，即可恢复旧视觉而不改变业务状态。

## Step 3. Remove Capability Center And Merge Capabilities Into Plugins

按“先迁移入口、后删除旧 View”的顺序修改：

- [ ] `PluginsSettingsView.swift` 观察现有 `SettingsStore`，在插件列表加入按插件/能力元数据
      过滤的上下文搜索。
- [ ] 在现有能力分段显示用途、适用内容、示例、固定/未固定状态；固定操作只调用
      `SettingsStore.setPinned`。
- [ ] 达到四项上限时禁用新的固定；停用插件的能力不可固定；已固定项可取消。
- [ ] 移除详情内部不必要的嵌套 inset/card，但保留导入、启停、配置、卸载、开发来源和
      错误流程。
- [ ] `CapabilitiesSettingsView.swift` 删除“可固定能力”目录，仅保留已固定项排序、取消和
      指向插件页的空状态说明。
- [ ] `ClipAllApp.swift` 删除独立 Window、菜单项和 `⌘⇧K`。
- [ ] 删除 `CapabilityCenterView.swift`，并更新 `Docs/Architecture.md`。

定向验证：

```bash
swift build --target ClipAll
if rg -n "CapabilityCenter|capability-center|能力中心" ClipAll Docs/Architecture.md; then
  exit 1
fi
Scripts/verify-overlay-state.sh
```

手动定向检查：插件搜索始终返回插件行；内置/开发/本地与停用状态正确；能力可固定、取消，
达到四项时解释禁用；操作栏仍能上移、下移和取消。

Rollback point：若插件详情未完整承接查看/固定，整体恢复旧 View、scene 和菜单，不能只删入口。

## Step 4. Apply The Settings Hierarchy

- [ ] `SettingsRootView.swift` 保持五项导航和两列窗口，移除品牌 hero card，用 sidebar、
      canvas、selected edge 和页面头部建立层级。
- [ ] `SelectionSettingsView.swift` 改用共享页面/flat section，保留全部 toggle、App 规则、
      picker、移除和文件选择行为。
- [ ] `GeneralSettingsView.swift` 改用共享页面/flat section和语义状态色，保留快捷键恢复、
      Dock/Menu Bar 至少一个入口和权限动作。
- [ ] `CapabilitiesSettingsView.swift` 使用同一页面骨架；本步只做视觉收口，不再增加能力目录。
- [ ] `DeveloperSettingsView.swift` 改用共享页面/flat section，明确关闭态；保留开发引用、
      reload、debug、remove 和诊断行为。
- [ ] `PluginsSettingsView.swift` 让列表成为唯一结构 surface，详情属于 content plane。
- [ ] `PluginConfigurationForm.swift` 把字段宽度收敛成自适应标签/控制列，不改字段或存储。

定向验证：

```bash
swift build --target ClipAll
rg -n "ClipAllSectionCard|\.foregroundStyle\(\.orange\)|Color\.green" \
  ClipAll/Features/Settings ClipAll/Features/PluginManagement
```

手动定向检查：五个导航页、插件配置和插件能力的 hover/pressed/focus/selected/disabled/empty/
error 状态，所有原有控件仍可达且没有窄窗裁切。

Rollback point：每个设置页可单独回退；共享 Theme 不回退时旧页面仍应可编译。

## Step 5. Restyle The Selection Overlay Without Behavior Changes

仅修改 `ClipAll/Features/SelectionOverlay/SelectionOverlayView.swift`：

- [ ] 外层改为一层原生 material、语义 overlay surface、hairline border 和 floating shadow。
- [ ] 从现有 phase capability ID 派生 active 按钮蓝色高亮；不新增 Published state。
- [ ] 统一 action、more、result、translation 和 error 的明暗视觉，保留按钮顺序、closure 和
      28 + 4 点高度组成的 36 点 compact bar。
- [ ] Reduce Motion 下移除旋转/缩放空间反馈，Reduce Transparency 下使用实色 surface。
- [ ] 不添加原文/译文箭头、连接线或方向动效；不修改推荐路由。

禁止修改：`SelectionOverlayStore.swift`、`SelectionOverlayCoordinator.swift`、
`OverlayPlacement.swift`。

定向验证：

```bash
swift build --target ClipAll
Scripts/verify-overlay-state.sh
```

手动定向检查：ready、推荐、更多、执行、结果、翻译、错误；compact 为 324 × 36，展开时
顶边不跳，搜索不自动抢焦点，显式点击可输入，Escape/外点/来源切换正常，普通键盘与 IME
不被拦截。

Rollback point：该 View 可单独回退；任何焦点或锚点回归都先回退视觉变更，不改 Coordinator。

## Step 6. Static Audit And Full Quality Gate

```bash
git diff --check
zsh -n Scripts/*.sh
swift build --target ClipAll
Scripts/verify-all.sh
```

- [ ] 静态确认 `ClipAll/` 和当前架构文档无能力中心概念。
- [ ] 静态检查改动 feature 不包含新的品牌 raw `Color(...)`、feature-local shadow、重复 spacing/
      radius；系统原生 destructive/warning 语义允许存在，但普通强调只使用 cobalt blue。
- [ ] 核对 diff 只含任务文件，`design-qa.md` 未改变。
- [ ] 使用 `trellis-check` 做 PRD、设计规范、行为兼容和最小实现复核。

## Step 7. Install And Real-App Visual QA

首选稳定本地签名：

```bash
Scripts/install-local-app.sh
```

如果缺少本地签名身份，不运行会持久创建受信证书的 setup 脚本；改用
`CLIPALL_ADHOC=1 Scripts/install-local-app.sh` 做低风险测试安装，并明确提示辅助功能权限可能
重置。

在 `/Applications/ClipAll.app` 完成：

- [ ] 浅色、深色分别截图：取词、通用、操作栏、插件列表/配置/能力、开发者关闭/开启。
- [ ] 以同一窗口尺寸将截图与 `Docs/Images/clipall-ui-design-light.png`、
      `Docs/Images/clipall-ui-design-dark.png` 并排比较，修复明显色阶、留白、密度、边框和圆角偏差。
- [ ] 浅色、深色分别截图浮窗 ready、更多、翻译结果或普通结果、错误状态。
- [ ] 抽查插件调试器、导入/卸载 sheet，确认共享 Theme 没有造成不可读回归。
- [ ] 检查 Reduce Motion、Reduce Transparency 和 Increase Contrast。
- [ ] 走一遍取词设置、通用入口、插件启停/配置/固定、操作栏排序、开发引用和浮窗执行主流程。

## Finish Gate

- 用户在真实 App 中明确表示测试通过前，不 commit、不归档、不声称任务完成。
- 用户通过后运行 `trellis-update-spec` 复核设计规范是否需要补充，只记录可复用合同。
- 提交只纳入本任务文件，格式使用 `feat(ui): ...` 的中文动词摘要。
- 最后运行 `trellis-finish-work`；不自动 push。

## Deferred

- 新插件能力、能力推荐算法、主题选择器、自定义动效系统。
- App 图标、菜单栏图标、来源 App 选区以及概念图中的未实现功能。
- UI snapshot 测试框架；当前项目没有 XCTest target，不为本任务新增空测试架构。
