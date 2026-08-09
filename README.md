<p align="center">
  <img src="Support/AppIcon.png" width="112" height="112" alt="ClipAll 图标">
</p>

<h1 align="center">ClipAll</h1>

<p align="center">面向 macOS 的本地选词能力平台：选中文字，立即复制、搜索、翻译或交给插件处理。</p>

> 当前处于开发阶段，仅提供源码和本地构建流程，尚无 Release、DMG 或安装器。

## 功能

- 在支持 Accessibility 选区的 App 中读取选中文字和选区位置。
- 使用不抢焦点的悬浮操作栏执行复制、搜索、翻译和插件能力。
- 固定常用能力，并按内容特征显示一条推荐；其余能力通过“更多”搜索和最近使用访问。
- 搜索支持 Google、Bing、DuckDuckGo，并通过默认浏览器打开。
- 翻译支持 Apple 系统设备端翻译和 HTTPS OpenAI-compatible API。
- 外置 `.clipallplugin` 支持导入、确认、启停、替换、卸载、配置、开发引用、重载和调试。
- 随构建包提供时间工具示例插件，支持 Unix 时间戳与日期双向转换。

## 环境要求

- macOS 15 或更高版本
- Swift 6
- Xcode Command Line Tools

核心构建和自动验证不要求完整 Xcode；系统翻译模型、辅助功能取词和界面验收需要真实 macOS 桌面环境。

## 快速开始

首次构建先创建一个仅供本机开发使用的稳定签名身份：

```sh
./Scripts/setup-local-signing.sh
./Scripts/build-local-app.sh
open .build/ClipAll.app
```

构建产物位于 `.build/ClipAll.app`，其中已嵌入独立 Runner、App 图标、菜单栏图标和可导入的时间工具示例。需要固定放在“应用程序”目录时，可在 Finder 中将这个 App 拖入 `/Applications`。

第一次取词时，请在“系统设置 → 隐私与安全性 → 辅助功能”中授权 ClipAll。默认快捷键为 `⌃⌥Space`，也可以通过菜单栏手动显示当前选区。

临时 CI 或一次性产物可以使用 ad-hoc 签名，但重新构建后可能需要重新授权辅助功能：

```sh
CLIPALL_ADHOC=1 ./Scripts/build-local-app.sh
```

## 使用流程

1. 启动 ClipAll，并确认菜单栏中的监控开关已开启。
2. 在其他 App 中选择一段文字。
3. 从浮层执行复制、搜索、翻译、推荐能力，或展开“更多”查找插件。
4. 在“设置 → 能力”调整固定能力；在“设置 → 插件”管理配置和生命周期。
5. 需要开发插件时，开启开发者模式并加载未打包的 `.clipallplugin` 目录。

复制成功后浮层会立即关闭。搜索和插件能力只会在用户明确点击后执行，路由匹配不会自动运行能力。

## 外置插件

一个最小插件是普通目录包：

```text
Example.clipallplugin/
├── plugin.json
└── main.js
```

`plugin.json` 声明插件信息、配置字段、能力和路由规则；`main.js` 暴露 `ClipAllPlugin.run(request)`，返回标题、副标题和可复制结果项。

时间工具示例位于 [`Plugins/Examples/TimestampTools.clipallplugin`](Plugins/Examples/TimestampTools.clipallplugin)。它不参与主 App 编译，也不会自动进入能力注册表；用户仍需通过普通导入确认流程安装。

插件合同与调试说明：

- [Plugin SDK 概览](Docs/PluginSDK/README.md)
- [Manifest v1](Docs/PluginSDK/manifest-v1.md)
- [Runtime v1](Docs/PluginSDK/runtime-v1.md)
- [开发与调试](Docs/PluginSDK/debugging.md)

## 隐私与安全

- 辅助功能权限只用于读取当前选中文字、选区位置和触发来源；选中文字不落盘。
- Apple 系统翻译在设备端执行。只有用户点击 AI 翻译时，所选文字才会发送到用户配置的 HTTPS endpoint。
- AI API Key 保存在 macOS Keychain，不写入普通配置文件或插件请求。
- 外置插件 v1 在独立短进程的 JavaScriptCore 中执行，没有宿主文件、网络、剪贴板、Accessibility、Shell 或原生对象访问能力。
- 本地 `.clipallplugin` 当前没有作者签名。格式和路径校验能阻止无效包，但不能证明作者身份。

## 工程结构

```text
ClipAll/
├── App/                     # 生命周期与依赖装配
├── Domain/                  # 稳定模型
├── Capabilities/            # 特征提取、路由、发现、注册表
├── BuiltInPlugins/          # 搜索与翻译
├── Features/                # 浮层、设置、能力中心、插件管理与调试
├── Infrastructure/          # Accessibility、持久化、Keychain、系统/翻译服务
├── PluginHost/              # Manifest、Validation、安装、生命周期与 Runtime
└── SharedUI/                # 无业务归属的主题与通用视图

ClipAllPluginProtocol/       # 主程序与 Runner 共用协议
ClipAllPluginRunner/         # 隔离执行外置 JavaScript
PluginSDK/                   # 机器可读 Schema
Plugins/Examples/            # 外置插件示例与 fixtures
Verification/               # CLT 可运行的验收程序
Scripts/                    # 构建、签名与验证入口
```

完整边界和数据流见 [工程架构](Docs/Architecture.md)。

## 验证

提交前可运行完整 CLT 验收：

```sh
./Scripts/verify-all.sh
```

也可以按模块单独运行：

```sh
./Scripts/verify-core.sh
./Scripts/verify-overlay-state.sh
./Scripts/verify-openai-translation.sh
./Scripts/verify-runner-client.sh
./Scripts/verify-plugin.sh Plugins/Examples/TimestampTools.clipallplugin
./Scripts/verify-lifecycle.sh Plugins/Examples/TimestampTools.clipallplugin
```

这些程序覆盖路由与发现、浮层定位与设置持久化、AI 翻译请求边界、Runner 超时/取消/协议故障、时间工具的 11 个 fixtures，以及插件 staging、receipt、替换和卸载流程。

`ClipAllTests` 当前只是 SwiftPM/XCTest 冒烟入口；主要回归验证仍由 `Verification/` 中的独立程序完成。真实取词、窗口位置、键盘焦点和系统翻译需要按 [本地开发与验收](Docs/Development.md) 手动验证。

## 当前限制

- 仅支持 macOS 15+，当前没有可下载的发布包。
- 外置插件 v1 只支持本地结果面板，不支持 secret、自定义 UI、打开 URL 或后台任务。
- Runner 默认执行超时为 750 ms，并限制请求、响应、日志和结果项大小。
- 本地构建会随 Swift SDK 和签名身份变化，不保证 bit-for-bit 可复现。
