# Plugin Runtime Protocol v2

## 脚本 API

入口脚本必须定义全局 `ClipAllPlugin` 对象。manifest 中每个 `handler` 对应该对象上的
函数，唯一参数是选中文字字符串：

```javascript
var pluginID = "com.example.clipall.tools";

var ClipAllPlugin = {
  convert: function (text) {
    var configuration = App.getPluginEnv(pluginID);
    return {
      title: "结果",
      subtitle: null,
      items: [{ id: "value", label: "值", value: text, style: "body" }]
    };
  }
};
```

`App.getPluginEnv(pluginID)` 返回 manifest 默认值与用户覆盖值合并后的普通配置对象；
无配置时返回 `{}`。ID 必须等于当前执行插件的稳定 manifest ID，空 ID 或其他插件 ID
会抛出 `invalid_plugin_id`。返回对象及其嵌套值只读，且不包含 secret。

handler 不会收到配置、locale、系统时区、来源应用、文件路径或宿主服务对象。需要本地
日期与语言信息时使用标准 JavaScript `Date` / `Intl`。Manifest 的 `inputMatchers` 只在
宿主路由阶段评估，不会传入 runner 或触发 handler。

## 成功输出

```json
{
  "title": "时间戳 → 日期",
  "subtitle": "Unix 秒级时间戳",
  "items": [{
    "id": "configured",
    "label": "UTC",
    "value": "2024-04-05T19:34:38.000Z",
    "annotation": "UTC · ISO 8601",
    "style": "monospaced"
  }]
}
```

- `title` 非空；`subtitle`、`annotation` 可为 `null`；
- `items` 为 1…12 项，item ID 在本次结果中唯一；
- `style` 为 `body` 或 `monospaced`；
- value 是可复制的纯文本，不会作为 HTML、Markdown、脚本或 URL 执行。

## 插件错误

插件通过抛出带稳定 code 的对象报告可预期错误：

```javascript
throw { code: "invalid_input", message: "请输入 10 位或 13 位 Unix 时间戳" };
```

code 使用小写 snake_case，message 面向用户且不包含输入正文。普通 JavaScript exception
映射为 `runtime_exception`；详细位置只在开发者调试器显示。

## 进程协议

宿主与 runner 使用匿名内存管道，通过 stdin/stdout 交换单个 JSON request/response，顶层
固定 `protocolVersion: 2`。内部 input 仅包含当前插件 ID、选中文字和只读普通配置快照；
它不是公开 handler 参数。Runner 先读取最小协议 envelope，再解码完整 v2 request；v1
request 返回 `unsupported_protocol`。

脚本文本由宿主读取并传入 runner；runner 不接收安装目录路径。Runner 验证结果结构，宿主
再次检查响应大小、协议版本，以及 status 与 output/error 的一致性。stderr 只由宿主排空，
不属于协议或调试日志。

每次执行创建新 runner 和 JavaScript context。默认期限 750 ms；超时、取消、非零退出、
stdout 污染、无效 JSON 或超限响应只影响当前插件。选中文字 UTF-8 上限为 65,536 bytes。

## Console

runner 提供内存 `console.log/warn/error`。正式执行丢弃日志；调试器可显示截断后的本次日志。
不要记录选中文字、配置值或转换结果正文。
