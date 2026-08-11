# POPO 双击正文运行证据

## Environment

- 日期：2026-08-11
- App bundle identifier：`com.netease.game.popo`
- ClipAll：稳定本地签名安装的诊断构建
- 操作：在同一段 POPO 正文上连续双击四次

## Sanitized Observation

四次捕获均满足以下事实：

```text
trigger=pointer-multiClick
fallbackPolicy=textHitRequired
initialError=noFocusedElement
delayedAXReadable=false
hitPath=<empty>
fallback suppressed=pointerTargetNotTextual
```

诊断探针等待 120ms 后再次执行完整 AX 捕获，仍无法读取选区。日志只记录错误枚举、布尔结果、bundle identifier 和空命中链，没有记录选中文字、控件标题或消息内容。

## Conclusion

POPO 该正文区域没有为 ClipAll 暴露可用的焦点 AX 元素，也无法从鼠标位置取得 AX 命中节点。失败不是 45ms 捕获时序过早，因此增加固定延时不会解决问题。

当前布尔命中谓词把空路径与明确非文字路径合并为 `false`，造成兼容性误杀。唯一调用者只需要允许 / 拒绝，因此无需新增三态类型：空路径直接允许进入现有受约束剪贴板回退，明确非文字路径继续拒绝。

## Constraints Retained

- 不添加 POPO bundle 白名单。
- 明确文件树、Tab、按钮等非文字 AX 路径仍在发送 `Command-C` 前拒绝。
- 复制结果仍需通过 changeCount、纯文本、对象类型、稳定性和并发恢复检查。
- 临时诊断探针必须在实现中删除。

## Post-Fix Verification

稳定签名版本安装到 `/Applications/ClipAll.app` 后，正式日志确认：

```text
POPO multi-click -> AX unavailable -> source=clipboard -> resolved
VSCodium Tab -> pointerTargetNotTextual -> suppressed
VSCodium text -> source=clipboard -> resolved
DevEco file tree -> pointerTargetNotTextual -> suppressed
DevEco text -> source=ax -> resolved
```

日志没有记录选中文字或控件内容。用户随后确认 POPO、IDE 文件树、VSCodium 正文 / Tab、输入框和普通单击手测通过。
