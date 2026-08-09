# ClipAll 本地开发与验收

## 环境

- macOS 15 或更高版本；
- Swift 6 与 Command Line Tools；
- 完整 Xcode 不是命令行核心验证的前置条件，但系统翻译模型和完整 GUI 验收需要在真实 macOS 桌面环境完成。

## 构建可运行 App

```sh
./Scripts/setup-local-signing.sh  # 仅首次运行
./Scripts/build-local-app.sh
open .build/ClipAll.app
```

首次设置会在登录钥匙串创建 `ClipAll Local Development` 本地 Code Signing 身份。后续构建始终复用该身份，使 macOS 在代码变化后仍把它识别为同一个 App。该证书只用于本机开发，不用于分发。

构建脚本会生成 `.build/ClipAll.app`，嵌入 Runner 和可导入的 `TimestampTools.clipallplugin`，使用固定本地身份签名并执行完整性检查。只有一次性 CI 产物需要临时签名时，才显式运行：

```sh
CLIPALL_ADHOC=1 ./Scripts/build-local-app.sh
```

App 第一次取词需要“系统设置 → 隐私与安全性 → 辅助功能”授权。开发期间请始终从固定路径 `.build/ClipAll.app` 启动；只要本地证书、bundle ID 和路径不变，后续构建无需重复授权。

## 自动验证

```sh
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
2. 在任意支持 Accessibility 选区的 App 中选择文字，确认非激活浮层出现在选区附近。
3. 验证复制、搜索、翻译、推荐、“更多”搜索、Esc/外点关闭以及最近使用。
4. 在“设置 → 插件”安装时间工具示例，再选择 `1712345678` 与 `2024-04-05T19:34:38Z`，分别执行两个方向并复制结果。
5. 验证插件停用、重新启用、保留配置卸载和删除配置卸载。
6. 开启开发者模式，加载未打包插件，验证重新载入、当前配置、单次执行、日志和 11 个 fixtures。

系统翻译首次使用可能由 macOS 准备或下载语言模型；AI 翻译只接受带 host 的 HTTPS endpoint，API key 存在 Keychain 中。
