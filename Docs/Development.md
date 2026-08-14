# ClipAll 本地开发与验收

当前源码版本由根目录 [`VERSION`](../VERSION) 管理（`0.0.7`）。修改版本时必须同步 `Support/ClipAll-Info.plist` 的 `CFBundleShortVersionString` 和 `CFBundleVersion`，然后运行：

```sh
./Scripts/check-version.sh
```

## 环境

- macOS 15 或更高版本；
- Swift 6 与 Command Line Tools；
- 完整 Xcode 不是命令行核心验证的前置条件，但系统翻译模型和完整 GUI 验收需要在真实 macOS 桌面环境完成。

## 构建可运行 App

```sh
./Scripts/setup-local-signing.sh  # 仅首次运行
./Scripts/install-local-app.sh
```

首次设置会在登录钥匙串创建 `ClipAll Local Development` 本地 Code Signing 身份。后续构建始终复用该身份，使 macOS 在代码变化后仍把它识别为同一个 App。该证书只用于本机开发，不用于分发。

安装脚本先生成并验证 SwiftPM debug `.build/ClipAll.app` 中间包，然后只替换和启动 `/Applications/ClipAll.app`。替换前会退出当前 Applications 版本，并把旧 App 备份到临时目录，避免同一 Bundle ID 从两个路径同时运行。只有一次性 CI 产物需要临时签名时，才直接运行：

```sh
CLIPALL_ADHOC=1 ./Scripts/build-local-app.sh
```

App 第一次取词需要“系统设置 → 隐私与安全性 → 辅助功能”授权。开发期间始终运行固定路径 `/Applications/ClipAll.app`；不要启动 `.build` 中间包。只要本地证书、bundle ID 和 Applications 路径不变，后续构建无需重复授权。

## 自动验证

```sh
./Scripts/check-version.sh
./Scripts/verify-core.sh
./Scripts/verify-plugin.sh Plugins/Examples/TimestampTools.clipallplugin
./Scripts/verify-lifecycle.sh Plugins/Examples/TimestampTools.clipallplugin
./Scripts/verify-runner-client.sh
./Scripts/verify-overlay-state.sh
./Scripts/verify-openai-translation.sh
```

这些检查分别覆盖内容特征与路由、时间工具 fixtures、插件安装生命周期、Runner 超时/取消/协议故障、浮层定位与设置持久化，以及 OpenAI-compatible 翻译请求与错误处理。

## 手动主流程

1. 启动 App，确认通用设置中的辅助功能权限为“已授权”，并开启自动取词。
2. 在 TextEdit、Safari、一个 Chromium/Electron App 和微信中分别拖选、双击及 Shift-click；确认 AX 可用时直接显示，AX 不提供选区但 `⌘C` 可用时进入兼容取词，且原剪贴板保持不变。
3. 对已高亮文字普通单击并继续输入，确认不弹旧选区、不产生双倍输入；安全输入框不得捕获。
4. 在“设置 → 通用”关闭兼容取词并排除一个 App，确认两种情况都只运行 AX；重新启动后开关和名单保持。
5. 验证复制、粘贴、搜索、翻译、推荐、“更多”搜索、Esc/外点关闭以及最近使用。
6. 在“设置 → 插件”安装时间工具示例，再选择 `1712345678` 与 `2024-04-05T19:34:38Z`，分别执行两个方向并复制结果。
7. 验证插件停用、重新启用时保留配置；卸载后重新安装恢复 manifest 默认值。
8. 开启开发者模式，加载未打包插件，验证重新载入、当前配置、单次执行、日志和 13 个 fixtures。

系统翻译首次使用可能由 macOS 准备或下载语言模型；AI 翻译只接受带 host 的 HTTPS endpoint，API key 存在 Keychain 中。

## Release 限制

推送形如 `vX.Y.Z` 的 tag 会由 GitHub Actions 在 `macos-15` arm64 runner 上检查 tag 与 `VERSION` 一致性、运行完整验证并构建 Latest Release。发布同时提供带 Applications 快捷入口的 ad-hoc DMG、备用 zip 和各自 SHA-256 校验文件；流程不使用 Developer ID 签名，也不执行 notarization。

因此下载的 Release 可能触发 Gatekeeper 的“无法验证开发者”提示，用户需要在 Finder 中明确允许打开，并自行确认来源可信。首次取词还必须在“系统设置 → 隐私与安全性 → 辅助功能”中授权 ClipAll；ad-hoc 身份或替换 App 后，macOS 可能要求重新授权。正式签名、公证、自动更新和生产分发属于后续工作。
