# Plugin Runtime Protocol v1

## 脚本 API

入口脚本必须定义全局 `ClipAllPlugin` 对象。manifest 中每个 `handler` 对应该对象上的一个函数：

```javascript
var ClipAllPlugin = {
  convert: function (request) {
    // request 只读；返回一个结构化结果对象。
  }
};
```

`request`：

```json
{
  "text": "1712345678",
  "configuration": { "timeZone": "utc" },
  "localeIdentifier": "zh-Hans-CN",
  "systemTimeZoneIdentifier": "Asia/Shanghai"
}
```

插件不能获得选区来源应用、文件路径或宿主服务对象。需要当前时间的行为不属于确定性转换；v1 不提供 `now` 注入。

Manifest 的 `inputMatchers` 只在宿主路由阶段评估，不会传入 runner，也不会触发 handler。执行时插件仍只应信任并校验 `request.text`。

## 成功输出

```json
{
  "title": "时间戳 → 日期",
  "subtitle": "Unix 秒级时间戳",
  "items": [
    {
      "id": "configured",
      "label": "UTC",
      "value": "2024-04-05T19:34:38.000Z",
      "annotation": "UTC · ISO 8601",
      "style": "monospaced"
    }
  ]
}
```

- `title` 非空；`subtitle`、`annotation` 可为 `null`。
- `items` 为 1…12 项，item ID 在本次结果中唯一。
- `style` 为 `body` 或 `monospaced`。
- value 是用户可复制的纯文本。HTML、Markdown、脚本和 URL 不会作为可执行内容处理。

## 插件错误

插件通过抛出带稳定 code 的对象报告可预期错误：

```javascript
throw { code: "invalid_input", message: "请输入 10 位或 13 位 Unix 时间戳" };
```

code 使用小写 snake_case，message 面向用户且不包含输入正文。普通 JavaScript exception 会映射为 `runtime_exception`；详细位置只在开发者调试器显示。

## 进程协议

宿主与 runner 使用 stdin/stdout 交换单个 JSON request/response，顶层包含 `protocolVersion: 1`。脚本文本由宿主读取并传入 runner；runner 不接收安装目录路径。Runner 负责验证结构化结果的字段、数量和字符串限制；宿主再次检查响应大小、协议版本，以及 status 与 output/error 的一致性。

每次能力执行创建新 runner 和 JavaScript context。默认执行期限 750 ms；超时、取消、非零退出、stdout 污染、无效 JSON 或超限响应都会成为当前插件执行错误，不影响主 App。选中文字的 UTF-8 输入上限为 65,536 bytes。

## Console

runner 提供纯 JavaScript 的内存 `console.log/warn/error`。正式能力执行丢弃日志；插件调试器可显示截断后的本次会话日志。不要写入选中文字、配置值或转换结果正文。
