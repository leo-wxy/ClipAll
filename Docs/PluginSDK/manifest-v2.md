# Plugin Manifest v2

`plugin.json` 使用 UTF-8 JSON。机器可读合同位于
`PluginSDK/Schemas/plugin-manifest-v2.schema.json`；本页解释字段语义。

## 顶层字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `manifestVersion` | integer | v2 固定为 `2` |
| `id` | string | 稳定的反向域名标识，如 `com.example.clipall.tools` |
| `name` | string | 用户可见插件名 |
| `version` | string | 三段 SemVer，如 `1.2.0` |
| `minimumClipAllVersion` | string | 可运行的最低宿主版本 |
| `summary` | string | 一句话用途 |
| `symbolName` | string | SF Symbol；不可用时宿主使用兜底图标 |
| `runtime` | object | v2 只支持 `javascriptCore` + 包内 `.js` 入口 |
| `configuration` | array | 可选配置字段，默认空数组 |
| `capabilities` | array | 至少一个能力 |

未知字段会被拒绝，避免拼写错误被静默忽略。`version` 是插件版本；
`manifestVersion` 是清单合同版本；`minimumClipAllVersion` 是最低宿主版本。
新增兼容能力通常提升插件 minor 版本；清单发生不兼容变化才提升 `manifestVersion`。

## 配置字段

共同字段：`id`、`title`、可选 `summary`、`type`、`defaultValue`，以及可选
`visibleWhen`：

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

v2 支持：

- `choice`：字符串默认值必须等于某个 option ID；
- `toggle`：布尔默认值；
- `text`：字符串默认值，可提供 `placeholder`。

field ID 在插件内唯一。`visibleWhen` 只能引用同插件字段，且比较值类型必须匹配。
外置 v2 不支持 `secret`。

## 能力字段

| 字段 | 说明 |
|---|---|
| `id` | 必须以 `<plugin-id>.` 开头 |
| `name` / `symbolName` / `purpose` | UI 展示和检索信息 |
| `examples` | 用户说明与检索示例；最多 12 项，每项最多 240 字符 |
| `exclusions` | 保留的排除说明；最多 12 项，每项最多 240 字符 |
| `executionKind` | v2 固定为 `resultPanel` |
| `handler` | `ClipAllPlugin` 全局对象上的函数名 |
| `routingRules` | 内容类型、分数和可解释理由 |

内容类型：`text`、`foreignLanguage`、`url`、`email`、`code`、`address`、
`unixTimestampSeconds`、`unixTimestampMilliseconds`、`dateTime`。

每条 routing rule 的 `score` 范围为 0…100。推荐仍由宿主阈值和用户固定项决定，
插件不能要求自动执行。

`exclusions` 当前只在导入时做格式与大小校验，不参与 UI、推荐、路由或 Runtime。
需要排除输入时，handler 仍须自行严格校验并返回明确错误。

### 声明式输入匹配

`routingRules[].inputMatchers` 是可选补充条件。当前只支持受限的 `dateFormat`：

```json
{
  "contentKind": "dateTime",
  "score": 97,
  "reason": "检测到明确的日期格式",
  "inputMatchers": [{
    "type": "dateFormat",
    "formats": ["yyyy-MM-dd", "yyyy年M月d日", "yyyy年M月d日 HH:mm:ss"]
  }]
}
```

- 支持 `yyyy`、`M`/`MM`、`d`/`dd`，以及成组出现的 `H`/`HH`、`m`/`mm`、
  `s`/`ss`；ASCII 字母常量用单引号包裹，例如 `'T'`。
- 每个格式必须包含年、月、日；声明时间时，时、分、秒必须同时存在。宿主执行完整
  字符串和 Gregorian 日历校验。
- 每条 routing rule 最多 4 个 matcher、每个 matcher 最多 16 个不重复格式、每个能力
  累计最多 32 个格式。
- matcher 只参与宿主推荐，不执行 JavaScript 或自动运行能力；handler 仍需严格校验输入。

## 包限制

- `plugin.json` ≤ 256 KB，入口脚本 ≤ 1 MB，整个包 ≤ 5 MB；
- 最多 256 个普通文件；拒绝符号链接和逃逸包根目录的路径；
- runtime entry 必须是至少 4 字符、大小写敏感的相对 `.js` 路径，解析后仍位于包根目录；
- capability、configuration 和 option ID 均不得重复。
