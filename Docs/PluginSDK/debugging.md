# 插件开发与调试

## 开发循环

1. 在 ClipAll 设置中开启“开发者模式”。
2. 进入“设置 → 开发者”，选择“载入未打包插件…”，再选择 `.clipallplugin` 目录。
3. manifest/schema 校验失败会显示在开发者页；只有成功加载的插件才能打开调试器。
4. 在调试器中查看或修改当前配置，为具体能力输入测试文本，检查内容特征、匹配分数与理由。
5. 执行 handler，检查结构化结果、耗时、错误 code 和本次 session 日志。
6. 修改 `plugin.json` 或 `main.js` 后手动“重新载入”。只有新版本完整通过校验，活动实例才会替换。

开发引用不会复制或删除源码目录。移除引用只会注销能力和删除 ClipAll 保存的引用元数据。

## Fixtures

可在 `Tests/cases.json` 提供数组：

```json
[
  {
    "name": "秒级时间戳",
    "capabilityID": "com.example.tools.timestamp-to-date",
    "input": "1712345678",
    "configuration": { "timeZone": "utc" },
    "expect": {
      "itemValues": { "utc": "2024-04-05T19:34:38.000Z" }
    }
  },
  {
    "name": "拒绝模糊数字",
    "capabilityID": "com.example.tools.timestamp-to-date",
    "input": "1234",
    "expectError": "invalid_input"
  }
]
```

fixture 使用已校验插件包中的同一 handler 和 runner，不允许导入宿主测试代码。每个 case 的 `configuration` 会直接作为运行配置发送，因此字段和值必须与 manifest 自行保持一致。对系统时区敏感的 case 应显式设置配置和期望环境。

## 常见失败

- `manifest_schema`：字段缺失、未知字段或类型不匹配；按 JSON pointer 修正。
- `invalid_identifier`：plugin/capability/field/handler ID 不符合约束。
- `unsafe_path`：入口逃逸包根、存在符号链接或不允许的文件类型。
- `registry_conflict`：plugin 或 capability ID 与活动插件冲突。
- `runtime_exception`：handler 抛出非协议错误或 JavaScript 执行失败。
- `runner_failure`：Runner 缺失、超时、崩溃、响应过大或协议无法解码；先检查进程与输入规模。
- `runtime_exception`：JavaScript 执行异常。
- `invalid_output`：结果结构不符合协议限制。

## 发布前检查

- 使用稳定 ID，不把版本号写进 plugin/capability ID。
- 对无效、越界和歧义输入返回确定错误，不猜测。
- 所有配置组合都有 fixture，尤其是条件字段和格式选项。
- 日志不包含用户正文、结果正文或配置值。
- 从一个全新的目录执行导入、停用、启用、替换和卸载流程。

仓库内置的命令行验收入口：

```sh
./Scripts/verify-plugin.sh Plugins/Examples/TimestampTools.clipallplugin
./Scripts/verify-lifecycle.sh Plugins/Examples/TimestampTools.clipallplugin
./Scripts/verify-runner-client.sh
```
