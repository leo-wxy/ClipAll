# 设置 Dock 与菜单栏图标显示

## Goal

让用户在“通用”设置中分别控制 ClipAll 的 Dock 图标和菜单栏图标，减少不需要的常驻入口，同时避免把两个入口都关闭后无法重新打开 App。

## Background

- 当前菜单栏入口由 `ClipAll/App/ClipAllApp.swift` 的 `MenuBarExtra` 常驻创建。
- 当前 Dock 图标由 `ClipAll/App/AppDelegate.swift` 固定设置 `.regular` activation policy。
- 用户设置统一由 `ClipAll/Infrastructure/Persistence/SettingsStore.swift` 通过 `UserDefaults` 持久化。

## Requirements

- 在“设置 → 通用”增加“显示菜单栏图标”和“显示 Dock 图标”两个独立开关。
- 两个开关默认都开启，并在 App 重启后保持用户选择。
- 设置变化应即时生效，不要求退出或重新启动 ClipAll。
- 菜单栏图标关闭时移除 `MenuBarExtra`；重新开启时恢复原菜单和图标。
- Dock 图标关闭时切换为 accessory activation policy；重新开启时恢复 regular activation policy。
- 两个入口至少保留一个。UI 应禁止关闭最后一个可见入口，持久化层也必须维护同一约束。
- 不改变自动取词、全局快捷键、窗口内容或插件行为。

## Out of Scope

- 登录时启动。
- 应用图标或菜单栏图标的视觉重设计。
- 隐藏所有入口后通过后台命令恢复的高级模式。

## Acceptance Criteria

- [ ] 关闭 Dock 图标后，Dock 中的 ClipAll 即时消失，菜单栏入口继续可用。
- [ ] 关闭菜单栏图标后，菜单栏入口即时消失，Dock 入口继续可用。
- [ ] 重新开启任一入口后，对应图标即时恢复。
- [ ] 重启 `/Applications/ClipAll.app` 后，两项选择保持不变。
- [ ] 当只剩一个入口可见时，不能再关闭该入口。
- [ ] 隐藏或恢复入口不会停止自动取词，也不会创建重复窗口或重复菜单栏图标。

## Key Decisions

- 这是轻量任务，仅保留 PRD，不新增设计文档或实施文档。
- 默认值延续当前行为：Dock 与菜单栏均显示。
- 安全约束选择“至少保留一个入口”，不提供完全隐身模式。
