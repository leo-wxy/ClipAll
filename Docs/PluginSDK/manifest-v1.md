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

版本分为三层：`version` 是插件自己的三段 SemVer；`manifestVersion` 是清单合同版本；`minimumClipAllVersion` 是该插件包所需的最低宿主版本。新增能力或输入格式通常提升插件 minor 版本；只有清单结构发生不兼容变化时才提升 `manifestVersion`。

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

### 声明式输入匹配

`routingRules[].inputMatchers` 是可选的补充匹配条件。v1 当前只支持受限的 `dateFormat`，用于让日期插件声明自身能够解析的本地日期形状：

```json
{
  "contentKind": "dateTime",
  "score": 97,
  "reason": "检测到明确的日期格式",
  "inputMatchers": [
    {
      "type": "dateFormat",
      "formats": ["yyyy-MM-dd", "yyyy年M月d日", "yyyy年M月d日 HH:mm:ss"]
    }
  ]
}
```

- `dateFormat` 支持 `yyyy`、`M`/`MM`、`d`/`dd`，以及成组出现的 `H`/`HH`、`m`/`mm`、`s`/`ss`；ASCII 字母常量需单引号包裹，例如 `'T'`。
- 每个格式必须包含年、月、日；如果声明时间，则时、分、秒必须同时存在。宿主会进行完整字符串和真实 Gregorian 日历校验，不接受自动进位日期。
- 每条 routing rule 最多 4 个 matcher、每个 matcher 最多 16 个不重复格式，每个能力累计最多 32 个格式。
- matcher 在宿主本地参与推荐，不会执行 JavaScript、不会访问系统服务，也不会自动运行能力。handler 仍需独立严格解析输入并返回明确错误。
- 没有 `inputMatchers` 的旧 v1 插件继续使用内容类型路由；使用该字段的插件应把 `minimumClipAllVersion` 设为 `0.0.3` 或更高。

## 包限制

- `plugin.json` ≤ 256 KB，入口脚本 ≤ 1 MB，整个包 ≤ 5 MB。
- 最多 256 个普通文件；符号链接和逃逸包根目录的路径会被拒绝。
- runtime entry 必须是相对路径、以 `.js` 结尾，且解析后仍位于包根目录。
- 一个插件的 capability、configuration 和 option ID 均不得重复。
