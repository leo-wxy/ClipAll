# ClipAll Plugin SDK

ClipAll 外置插件是后缀为 `.clipallplugin` 的目录 package。v1 面向“根据选中文字产生结构化结果”的本地转换能力：插件声明匹配规则、配置和 handler，宿主负责推荐、配置界面、结果 UI、复制与生命周期。

## 最小插件

```text
MyPlugin.clipallplugin/
├── plugin.json
└── main.js
```

插件脚本暴露一个全局对象：

```javascript
var ClipAllPlugin = {
  run: function (request) {
    return {
      title: "结果",
      subtitle: null,
      items: [
        { id: "value", label: "值", value: request.text, style: "body" }
      ]
    };
  }
};
```

完整字段见 [manifest-v1.md](manifest-v1.md)，执行环境见 [runtime-v1.md](runtime-v1.md)，开发与排错见 [debugging.md](debugging.md)。参考实现位于 `Plugins/Examples/TimestampTools.clipallplugin`。

每个外置插件都是一个独立目录，插件自己的 manifest、脚本、说明和 fixtures 都放在该目录中。宿主只通过公开的 manifest/runtime 合同加载它，不把插件源码编译进主 App。

## 匹配与外显

插件通过每个 capability 的 `purpose`、`examples`、`exclusions` 和 `routingRules` 描述自己适合处理的内容。日期能力可以额外在 routing rule 中声明受限的 `dateFormat` 输入匹配器。宿主先提取选中文字的内容特征并评估声明式匹配，再按规则计算分数：

- 固定能力由用户决定，常驻操作栏；
- 推荐能力最多显示一个，必须由用户点击执行；
- 其余能力进入“更多”，支持按名称、用途和插件名搜索；
- 插件永远不能因为匹配成功而自动执行。

## 生命周期

1. 导入：宿主复制到 staging，完成结构、schema、大小、路径和冲突校验。
2. 确认：用户看到来源、版本、能力、配置与权限摘要。
3. 安装：宿主原子移动到 Application Support，写 receipt，再注册全部能力。
4. 启停：停用会注销全部能力但保留文件与配置；启用前重新校验。
5. 卸载：只删除宿主管理的安装副本；源包不变。配置默认保留，可由用户一并删除。
6. 开发引用：开发者模式可以直接引用源码目录并重载；移除引用永不删除源码。

## 时间工具示例

本地 App bundle 随附 `TimestampTools.clipallplugin`，但不会自动安装或静态注册。在“设置 → 插件”中点击“安装时间工具示例”，仍会经过与普通外置插件完全相同的校验、确认和安装流程。

该插件提供两个独立能力：

- 10/13 位 Unix 时间戳转日期；
- 数字日期、中文日期或 ISO 8601 文本转时间戳。

它支持“跟随系统 / UTC”时区和“标准 / ISO 8601 / 中文”显示格式。卸载只删除 ClipAll 管理的安装副本，不会删除 App 内的示例资源或用户选择的源目录。

## v1 安全边界

- JavaScript 在独立短生命周期 runner 中执行。
- 没有文件、网络、剪贴板、Accessibility、shell、自动化或原生对象桥接。
- 每次执行使用新 context，并受宿主超时、输入、输出和日志上限约束。
- 本地包没有作者签名或身份验证；通过格式校验不等于可信。
- v1 不支持 secret 配置、自定义 UI、外部 URL 或后台任务。

## 稳定性要求

- plugin ID 使用反向域名格式；capability ID 必须以 plugin ID 为前缀。
- 已发布 ID 不应复用或改义，否则用户固定项和配置无法稳定迁移。
- 插件自身使用三段 SemVer；增加兼容输入格式应提升 minor 版本，并保持 plugin/capability ID 不变。
- `manifestVersion` 只表示清单合同；使用宿主新字段时同步提高 `minimumClipAllVersion`。
- handler 必须是纯函数式行为：相同文本、配置、locale 与时区应产生相同结果。
- 不依赖宽松的日期、URL 或数字解析；无效或歧义输入应返回明确错误。
