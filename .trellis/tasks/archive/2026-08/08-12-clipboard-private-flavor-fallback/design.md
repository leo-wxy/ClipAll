# 原生 Pasteboard 完整快照设计

## Boundary

只修改 `ClipboardSelectionFallback` 的原剪贴板快照与恢复实现。捕获事务仍按以下顺序运行：

```text
AX 失败 -> 完整快照 -> 清空 -> 定向 Command-C -> 校验新结果 -> 恢复 -> 发布选区
```

`NSPasteboard` 继续负责 change count、新复制结果读取和对象类型过滤；公开 Pasteboard Manager 只负责原剪贴板的无损 flavor 读写。

## Data Model

快照保存在进程内存中：

- item：保持原顺序；恢复时使用新的进程内唯一 item identifier。
- flavor：保存原始类型字符串、`Data` 和调用方可设置的 `PasteboardFlavorFlags`。
- 过滤 `kPasteboardFlavorSystemTranslated`，避免把系统派生格式重复保存、触发额外转换或突破大小上限。
- 读取时可物化 promised flavor；恢复时数据已经存在，因此移除系统管理的 `promised` 与 `systemTranslated` flags。

## Compatibility

- 生产对象是实际 `NSPasteboard` 时走原生 flavor 快照/恢复。
- 现有测试 fake 继续使用当前 `NSPasteboardItem` 内存路径，保留确定性的超时、取消和并发状态机验证。
- 新增一个临时命名 `NSPasteboard` 集成场景，用原生 API 写入 AppKit 拒绝的 Qt 私有 flavor，验证捕获后字节级恢复。
- `Package.swift` 已链接 Carbon，预计无需新增依赖、target 或脚本。

## Failure And Ownership

- 快照阶段任何 API 错误、空 flavor 列表、数量或大小越界均映射为 `unsafePasteboard`，且不得先清空。
- 恢复前仍比较 `changeCount`；不属于本事务的 generation 返回 `clipboardChanged`。
- 原生 clear/put 任一步失败映射为 `restoreFailed`。
- 不记录类型名称、数据或选中文字；现有错误枚举日志足够定位阶段。

## Rollback

回滚 `ClipboardSelectionFallback.swift` 的原生 flavor 分支即可恢复当前 AppKit 快照行为；手势、AX、设置和 UI 不受影响。
