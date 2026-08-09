# Plugin Manifest v1

`plugin.json` 使用 UTF-8 JSON。机器可读合同位于 `PluginSDK/Schemas/plugin-manifest-v1.schema.json`；本页解释字段语义。

## 顶层字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `manifestVersion` | integer | v1 固定为 `1` |
| `id` | string | 反向域名标识，如 `com.example.clipall.tools` |
| `name` | string | 用户可见插件名 |
| `version` | string | 三段 SemVer，如 `1.2.0` |
| `minimumClipAllVersion` | string | 可运行的最低宿主版本 |
| `summary` | string | 一句话用途 |
| `symbolName` | string | SF Symbol；不可用时宿主使用兜底图标 |
| `runtime` | object | v1 只支持 `javascriptCore` + 包内 `.js` 入口 |
| `configuration` | array | 可选配置字段，默认空数组 |
| `capabilities` | array | 至少一个能力 |

未知顶层字段会被拒绝，避免拼写错误被静默忽略。

## 配置字段

共同字段：`id`、`title`、可选 `summary`、`type`、`defaultValue`，以及可选 `visibleWhen`：

```json
{
  "id": "displayFormat",
  "title": "显示格式",
  "type": "choice",
  "defaultValue": "standard",
  "options": [
    { "id": "standard", "title": "标准" },
    { "id": "iso8601", "title": "ISO 8601" }
  ],
  "visibleWhen": { "fieldID": "enabled", "equals": true }
}
```

v1 支持：

- `choice`：字符串默认值必须等于某个 option ID。
- `toggle`：布尔默认值。
- `text`：字符串默认值，可提供 `placeholder`。

field ID 在插件内唯一。`visibleWhen` 只能引用同插件字段，且比较值类型必须匹配。外置 v1 不支持 `secret`。

## 能力字段

| 字段 | 说明 |
|---|---|
| `id` | 必须以 `<plugin-id>.` 开头 |
| `name` / `symbolName` / `purpose` | UI 展示和检索信息 |
| `examples` / `exclusions` | 用户说明与未来语义路由合同 |
| `executionKind` | v1 固定为 `resultPanel` |
| `handler` | `ClipAllPlugin` 全局对象上的函数名 |
| `routingRules` | 内容类型、分数和可解释理由 |

内容类型 v1：`text`、`foreignLanguage`、`url`、`email`、`code`、`address`、`unixTimestampSeconds`、`unixTimestampMilliseconds`、`dateTime`。

每条 routing rule 的 `score` 范围为 0…100。结构化且可确定的内容可使用高分；通用文本能力应使用较低分，避免压过专用能力。推荐仍由宿主阈值和用户固定项决定，插件不能要求自动执行。

## 包限制

- `plugin.json` ≤ 256 KB，入口脚本 ≤ 1 MB，整个包 ≤ 5 MB。
- 最多 256 个普通文件；符号链接和逃逸包根目录的路径会被拒绝。
- runtime entry 必须是相对路径、以 `.js` 结尾，且解析后仍位于包根目录。
- 一个插件的 capability、configuration 和 option ID 均不得重复。
