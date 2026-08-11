# 跨应用选区捕获兼容设计

## Boundary

本次只调整双击 / 多击在 AX 失败后的回退判定。AX 选区读取、剪贴板快照与恢复、浮窗展示、能力执行和设置持久化均沿用现有实现。

只修改三个现有文件：

- `PointerSelectionGesture.swift`：让双击策略名称表达真实语义；
- `SelectionCaptureService.swift`：修正现有命中谓词和回退路由；
- `OverlayStateVerification.swift`：补空路径回归并保留既有误触案例。

## Root Cause

当前 `SelectionHitClassifier.supportsTextSelection` 返回布尔值，空路径与明确非文字路径都返回 `false`。调用者因此无法让 POPO 这类 AX 完全不可用的 App 进入现有剪贴板回退。

POPO 的现场证据是空路径，而 IDE 文件树 / Tab 的既有证据是非空路径并包含明确角色、动作或缺少选区语义。两者可以在不识别 App 身份的情况下区分。

## Minimal Decision

不新增三态枚举。唯一调用者最终只需要允许 / 拒绝，因此把现有谓词改成直接表达策略：

```swift
SelectionHitClassifier.allowsClipboardFallback(in: path) -> Bool
```

规则按顺序执行：

1. 路径为空：返回 `true`，交给现有剪贴板结果校验。
2. 有任意 blocking role / action：返回 `false`。
3. 完整扫描后存在直接选区属性，或同时存在字符数与可见字符范围语义：返回 `true`。
4. 路径非空但没有文字选区语义：返回 `false`。

必须完整扫描有限路径后再接受，避免前层像正文、深层实际是 `AXRow` 的对象路径绕过拒绝。

双击策略从含糊的 `textHitRequired` 改名为 `rejectKnownNonText`。拖选保持无命中门槛，Shift-click 保持禁用回退。

## Data Flow

```text
明确选词手势
  -> AX 捕获
     -> 成功：SelectionContext -> 浮窗
     -> 失败且允许回退
        -> 双击：检查鼠标 AX 命中链
           -> 明确非文字 / 非空无文字语义：静默结束
           -> 文字语义 / 空路径：继续
        -> 现有 ClipboardSelectionFallback
        -> changeCount + 稳定性 + 类型 + 非空文本校验
           -> 通过：恢复快照 -> SelectionContext -> 浮窗
           -> 失败：安全恢复或保留并发新内容 -> 静默结束
```

## Privacy and Compatibility

- 不记录命中控件标题、值、路径文本或选中文字。
- 不新增临时文件或持久化选区数据。
- 不添加 POPO 白名单，任何 AX 完全不可用的 App 都走相同规则。
- `AXSecureTextField` 可见时继续硬拒绝。
- AX 完全不可见时无法预先识别安全控件；只读取来源 App 对用户触发 `Command-C` 后主动写入的纯文本，并保留全局开关与按 App 排除。

## Trade-off and Rollback

空路径放行比“所有双击直接复制”保留了已有 AX 误触过滤。剩余不可消除的情况是：完全不暴露 AX 的 App 在双击业务对象时主动把纯文本写入剪贴板；由类型过滤和按 App 排除兜底。

若手测发现不可接受的新增误触，只需把空路径恢复为拒绝；无 schema、持久化或接口迁移。
