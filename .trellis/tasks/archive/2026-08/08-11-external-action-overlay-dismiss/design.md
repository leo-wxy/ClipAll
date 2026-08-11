# 浮窗关闭与选择意图：技术设计

## Root Cause

当前能力执行链默认认为所有能力都需要浮窗内反馈：

```text
点击搜索
→ phase = executing
→ panel 按执行状态重新测量
→ 浏览器打开
→ output = external
→ phase = message
→ 等待 650ms
→ store.dismiss()
→ Coordinator 下一轮才 orderOut
```

外部副作用与浮窗内结果使用了同一个呈现合同，导致 Store、SwiftUI 和 AppKit 三层都发生了不必要的中间状态。

## Contract

在 `CapabilityExecuting` 增加内部执行呈现策略：

```swift
enum CapabilityExecutionPresentation {
    case overlay
    case external
}

var executionPresentation: CapabilityExecutionPresentation { get }
```

协议扩展默认返回 `.overlay`，现有翻译与外置插件无需修改；`SearchCapability` 明确返回 `.external`。

## Execution Flow

`SelectionOverlayStore.execute` 在 availability 校验后分流：

- `.overlay`：保持现有执行中、翻译、结果和失败流程。
- `.external`：先 `dismiss()`，再异步调用 executor；不设置 `isMorePresented`、`moreQuery` 或 `phase` 中间状态。成功只记录最近使用，失败只写结构化诊断日志。

外部执行任务仍保存到 `executionTask`，新选区出现时可以取消未完成的旧任务。外部能力若返回非 `.external` 输出，记录合同违例并忽略，不能重新显示旧上下文。

## Panel Lifecycle

Coordinator 保留 `objectWillChange` 负责可见状态下的尺寸变化，同时单独观察 `store.$isVisible.removeDuplicates()`：

- 变为 `false`：取消待执行的尺寸同步并立即 `orderOut`。
- 变为 `true`：现有 `present`/`synchronizePanel` 负责首次定位。

这样所有 Store 侧成功关闭，包括复制、粘贴和外部执行，都不会等待下一轮尺寸同步。

## Validation Seam

在 Overlay 状态验证中注册一个声明 `.external` 的测试 executor：

1. `store.present(context)`。
2. 同步调用 `store.execute(testID)`。
3. 立即断言 `isVisible == false`。
4. 等待 executor 完成，断言只执行一次并记录最近使用。

真实 panel 的同事件周期 `orderOut` 使用唯一前缀 frame 日志和 `/Applications/ClipAll.app` 手测确认；验证完成后删除临时日志。

## Pointer Intent And Fallback Gate

`PointerSelectionGesture.end` 不再返回无法表达语义的 `Bool`，改为：

```swift
enum PointerSelectionIntent: Equatable, Sendable {
    case drag
    case multiClick
    case shiftClick

    var fallbackPolicy: SelectionFallbackPolicy {
        switch self {
        case .drag: .enabled
        case .multiClick: .textHitRequired
        case .shiftClick: .disabled
        }
    }
}
```

判定优先级为 Shift-click、multiClick、drag；未形成明确动作时返回 `nil`。多击即使伴随超过 4pt 的轻微位移也保持 `multiClick`。拖选在 AX 失败时允许进入带对象类型校验的复制回退；多击还必须通过鼠标 AX 命中分类；Shift-click 保持 AX-only。注册快捷键和菜单命令属于显式动作，固定允许回退。

`SelectionCapturing.captureCurrentSelection` 接收 `SelectionFallbackPolicy`。`SelectionCaptureService` 只有在 AX 错误本身允许、设置允许且策略允许时才调用 `ClipboardSelectionFallback`。`.textHitRequired` 会遍历鼠标命中元素的有界祖先链：`AXSelectedText`、`AXSelectedTextRange`、Text Marker，或 NumberOfCharacters 与 VisibleCharacterRange 组合可证明文本表面。分类器必须先扫描完整路径，再接受文本证据；任一层出现 `AXPress` 等硬操作或按钮/Tab/列表角色均拒绝，未出现选区语义就到达 Window 也拒绝。`AXShowMenu` 在 Electron 文本节点上普遍存在，不能单独否决。不按 App bundle ID 或控件标题特判。

## Non-Text Pasteboard Rejection

`ClipboardSelectionFallback` 在观察到目标 App 写入新 generation 后，先检查全部新 item 的类型，再读取 `.string`。出现以下任一类型即抛出 `nonTextContent` 并按既有事务规则恢复快照：

- `public.file-url` / `NSFilenamesPboardType`；
- 动态 UTI 的 `com.apple.nspboard-type` tag 解析出的 `NSFilenamesPboardType`、`text/uri-list`、`x-special/gnome-copied-files` 或 Apple URL 类型；
- promised file URL 或 promised file content type。
- 已声明的 image、audio/video、PDF、archive、vCard 或 font UTI。

该检查针对“对象同时带纯文本表示”的误判，不能依赖字符串长相、扩展名、目标 App bundle ID 或一次运行生成的动态 UTI 哈希。Chromium 真文字的 source metadata、HTML 与纯文本组合继续允许。

## Rollback

回滚 `CapabilityExecutionPresentation` 分流、Coordinator 可见性订阅和指针 fallback gate 即可恢复旧行为；不涉及持久化、插件 schema、Runner 协议或用户数据迁移。
