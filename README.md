<p align="center">
  <img src="Support/AppIcon.png" width="112" height="112" alt="ClipAll 图标">
</p>

<h1 align="center">ClipAll</h1>

<p align="center">macOS 本地选词工具：选中文字，立即复制、粘贴、搜索、翻译或交给插件处理。</p>

<p align="center">macOS 15+ · Apple Silicon · 当前版本 0.0.9</p>

## 界面预览

<p align="center">
  <img src="Docs/Images/selection-overlay.png" width="600" alt="选中文字后的 ClipAll 浮窗">
</p>
<p align="center"><sub>选中文字后，就地复制、粘贴、搜索、翻译或展开更多能力。</sub></p>

<table>
  <tr>
    <td width="50%"><img src="Docs/Images/selection-settings.jpg" alt="ClipAll 取词设置与应用规则"></td>
    <td width="50%"><img src="Docs/Images/plugin-management.jpg" alt="ClipAll 插件管理与翻译配置"></td>
  </tr>
  <tr>
    <td align="center">按触发方式和来源 App 控制自动浮窗</td>
    <td align="center">集中管理内置能力、外置插件与配置</td>
  </tr>
</table>

## 功能

- 拖选、双击或 Shift-click 后显示悬浮操作栏，普通单击和普通输入不会触发。
- 可分别开关拖选与双击/多击，并按 App 设置“跟随全局”“仅拖选”或“永不自动显示”。
- 固定提供复制、粘贴、搜索和翻译，并按内容推荐其他能力。
- 优先通过 Accessibility 读取选区；微信等自绘控件可用临时复制回退，完成后恢复剪贴板。
- 支持 Apple 设备端翻译和用户配置的 HTTPS OpenAI-compatible API。
- 支持本地 `.clipallplugin` 的导入、配置、启停、卸载、重载和调试。

## 下载与安装

[下载最新 Release](https://github.com/leo-wxy/ClipAll/releases/latest)

Release 始终提供 arm64 ZIP，并在 GitHub Runner 支持磁盘镜像时同时提供 DMG；两者均使用 ad-hoc 签名且未经 Apple 公证。首次打开可能需要在 Finder 或“系统设置 → 隐私与安全性”中明确允许，并在“辅助功能”中授权 ClipAll。

从源码本地安装：

```sh
./Scripts/setup-local-signing.sh  # 仅首次运行
./Scripts/install-local-app.sh
```

安装脚本只更新并启动 `/Applications/ClipAll.app`；`.build/ClipAll.app` 仅是中间产物。更多说明见 [本地开发与验收](Docs/Development.md)。

## 使用

1. 启动 ClipAll，在“设置 → 取词”确认自动监听和需要的触发方式已开启。
2. 在其他 App 中拖选、双击或 Shift-click 选择文字。
3. 从浮层执行操作，或展开“更多”查找插件能力。

“自动监听文字选择”是总开关；关闭后鼠标自动取词和全局快捷键都会停止，菜单栏“显示当前选区”仍可手动使用。默认快捷键是 `⌃⌥Space`。触发方式、应用规则和兼容取词统一在“设置 → 取词”管理；密码框、安全输入框和无法复制的图像内容不会进入回退。

## 插件

最小插件是一个普通目录包：

```text
Example.clipallplugin/
├── plugin.json
└── main.js
```

时间工具示例位于 [`Plugins/Examples/TimestampTools.clipallplugin`](Plugins/Examples/TimestampTools.clipallplugin)，支持 Unix 时间戳、数字日期和中文日期双向转换。

- [Plugin SDK](Docs/PluginSDK/README.md)
- [Manifest v1](Docs/PluginSDK/manifest-v1.md)
- [Runtime v1](Docs/PluginSDK/runtime-v1.md)
- [插件调试](Docs/PluginSDK/debugging.md)

## 开发与验证

要求 macOS 15+、Swift 6 和 Xcode Command Line Tools。

```sh
./Scripts/check-version.sh
./Scripts/verify-all.sh
```

`verify-all` 覆盖核心路由、浮层状态、翻译、Runner、插件运行时和安装生命周期；CI 随后构建完整 App bundle。

完整边界和数据流见 [工程架构](Docs/Architecture.md)。真实取词、窗口焦点和系统翻译需要使用 `/Applications/ClipAll.app` 手动验收。

## 隐私与限制

- 选中文字不落盘；兼容取词的临时剪贴板内容只在内存中使用。
- 只有用户点击 AI 翻译时，文字才会发送到配置的 HTTPS endpoint；API Key 保存在 Keychain。
- 外置插件在独立 JavaScriptCore 进程中执行，没有文件、网络、剪贴板或 Accessibility 权限。
- 纯图片、远程桌面、DRM 内容或不响应系统复制的控件可能无法取词。
- 本地插件尚无作者签名；格式校验不能证明来源可信。

## 许可证

[MIT License](LICENSE)
