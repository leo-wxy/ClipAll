import AppKit
import Foundation

private enum OverlayStateVerificationError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

@main
@MainActor
enum OverlayStateVerification {
    static func main() async throws {
        try verifyPlacement()
        try verifyPointerSelectionGesture()
        try verifySelectionHitClassifier()
        try verifyEmptyPinnedPersistence()
        try await verifyClipboardSelectionFallback()
        print("Overlay state verification passed")
    }

    private static func verifyClipboardSelectionFallback() async throws {
        try await verifyClipboardScenario("多格式恢复", verifyClipboardFallbackRestoresAllTypes)
        try await verifyClipboardScenario("相同文本", verifyClipboardFallbackDetectsSameTextCopy)
        try await verifyClipboardScenario("超时恢复", verifyClipboardFallbackRestoresAfterTimeout)
        try await verifyClipboardScenario("并发写入", verifyClipboardFallbackPreservesExternalChange)
        try await verifyClipboardScenario("取消恢复", verifyClipboardFallbackRestoresAfterCancellation)
        try await verifyClipboardScenario("不安全快照", verifyClipboardFallbackRejectsUnsafeSnapshot)
        try await verifyClipboardScenario("文件对象", verifyClipboardFallbackRejectsFileObject)
        try await verifyClipboardScenario("动态文件对象", verifyClipboardFallbackRejectsDynamicFileObject)
        try await verifyClipboardScenario("图片对象", verifyClipboardFallbackRejectsImageObject)
        try await verifyClipboardScenario("Chromium 真文字", verifyClipboardFallbackAcceptsChromiumText)
    }

    private static func verifyClipboardScenario(
        _ name: String,
        _ verification: () async throws -> Void
    ) async throws {
        do {
            try await verification()
        } catch let error as OverlayStateVerificationError {
            throw error
        } catch {
            throw OverlayStateVerificationError.failed("剪贴板场景“\(name)”失败：\(error)")
        }
    }

    private static func verifyClipboardFallbackRestoresAllTypes() async throws {
        let pasteboard = VerificationPasteboard()
        defer { pasteboard.clearContents() }
        let rtf = Data("{\\rtf1 original}".utf8)
        writePasteboard(pasteboard, text: "original", rtf: rtf)

        let fallback = makeFallback(pasteboard: pasteboard) { _ in
            writePasteboard(pasteboard, text: "selected")
            return true
        }
        let text = try await fallback.captureSelection(sourceProcessIdentifier: 42)

        try expect(text == "selected", "复制回退应读取目标选区")
        try expect(pasteboard.string(forType: .string) == "original", "复制回退后应恢复原文字")
        try expect(pasteboard.data(forType: .rtf) == rtf, "复制回退后应恢复原富文本")
    }

    private static func verifyClipboardFallbackDetectsSameTextCopy() async throws {
        let pasteboard = VerificationPasteboard()
        defer { pasteboard.clearContents() }
        writePasteboard(pasteboard, text: "same")

        let fallback = makeFallback(pasteboard: pasteboard) { _ in
            writePasteboard(pasteboard, text: "same")
            return true
        }
        let text = try await fallback.captureSelection(sourceProcessIdentifier: 42)

        try expect(text == "same", "复制内容与原剪贴板相同时仍应依靠 changeCount 识别")
        try expect(pasteboard.string(forType: .string) == "same", "相同文字回退后仍应恢复剪贴板")
    }

    private static func verifyClipboardFallbackRestoresAfterTimeout() async throws {
        let pasteboard = VerificationPasteboard()
        defer { pasteboard.clearContents() }
        writePasteboard(pasteboard, text: "original")

        let fallback = makeFallback(
            pasteboard: pasteboard,
            timeout: .milliseconds(25)
        ) { _ in true }
        do {
            _ = try await fallback.captureSelection(sourceProcessIdentifier: 42)
            throw OverlayStateVerificationError.failed("复制无响应时应超时")
        } catch ClipboardSelectionFallbackError.timedOut {
            try expect(
                pasteboard.string(forType: .string) == "original",
                "复制超时后应恢复剪贴板"
            )
        }
    }

    private static func verifyClipboardFallbackPreservesExternalChange() async throws {
        let pasteboard = VerificationPasteboard()
        defer { pasteboard.clearContents() }
        writePasteboard(pasteboard, text: "original")

        let fallback = makeFallback(
            pasteboard: pasteboard,
            stabilityDelay: .milliseconds(30)
        ) { _ in
            writePasteboard(pasteboard, text: "selected")
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(5))
                writePasteboard(pasteboard, text: "external")
            }
            return true
        }
        do {
            _ = try await fallback.captureSelection(sourceProcessIdentifier: 42)
            throw OverlayStateVerificationError.failed("并发剪贴板变化应中止回退")
        } catch ClipboardSelectionFallbackError.clipboardChanged {
            try expect(
                pasteboard.string(forType: .string) == "external",
                "并发写入后不得覆盖用户的新剪贴板"
            )
        }
    }

    private static func verifyClipboardFallbackRestoresAfterCancellation() async throws {
        let pasteboard = VerificationPasteboard()
        defer { pasteboard.clearContents() }
        writePasteboard(pasteboard, text: "original")

        let fallback = makeFallback(
            pasteboard: pasteboard,
            timeout: .seconds(1)
        ) { _ in true }
        let task = Task { @MainActor in
            try await fallback.captureSelection(sourceProcessIdentifier: 42)
        }
        try await Task.sleep(for: .milliseconds(10))
        task.cancel()
        do {
            _ = try await task.value
            throw OverlayStateVerificationError.failed("取消时应停止复制回退")
        } catch is CancellationError {
            try expect(
                pasteboard.string(forType: .string) == "original",
                "取消复制回退后应恢复剪贴板"
            )
        }
    }

    private static func verifyClipboardFallbackRejectsUnsafeSnapshot() async throws {
        let pasteboard = VerificationPasteboard()
        defer { pasteboard.clearContents() }
        let items = (0..<17).map { index in
            let item = NSPasteboardItem()
            item.setString("item-\(index)", forType: .string)
            return item
        }
        pasteboard.clearContents()
        _ = pasteboard.writeObjects(items)
        let originalChangeCount = pasteboard.changeCount

        let fallback = makeFallback(pasteboard: pasteboard) { _ in
            throwIfReached("快照失败后不得发送复制")
        }
        do {
            _ = try await fallback.captureSelection(sourceProcessIdentifier: 42)
            throw OverlayStateVerificationError.failed("超出上限的剪贴板应拒绝回退")
        } catch ClipboardSelectionFallbackError.unsafePasteboard {
            try expect(
                pasteboard.changeCount == originalChangeCount,
                "无法安全快照时不得先清空剪贴板"
            )
            try expect(
                pasteboard.string(forType: .string) == "item-0",
                "无法安全快照时应保留原内容"
            )
        }
    }

    private static func verifyClipboardFallbackRejectsFileObject() async throws {
        let pasteboard = VerificationPasteboard()
        defer { pasteboard.clearContents() }
        writePasteboard(pasteboard, text: "original")

        let fallback = makeFallback(pasteboard: pasteboard) { _ in
            let item = NSPasteboardItem()
            item.setString("oh_modules", forType: .string)
            item.setString("file:///tmp/oh_modules", forType: .fileURL)
            pasteboard.clearContents()
            _ = pasteboard.writeObjects([item])
            return true
        }

        do {
            let text = try await fallback.captureSelection(sourceProcessIdentifier: 42)
            throw OverlayStateVerificationError.failed(
                "文件对象的纯文本表示不得触发浮窗，实际返回：\(text)"
            )
        } catch let error as OverlayStateVerificationError {
            throw error
        } catch ClipboardSelectionFallbackError.nonTextContent {
            try expect(
                pasteboard.string(forType: .string) == "original",
                "拒绝文件对象后应恢复原剪贴板"
            )
        }
    }

    private static func verifyClipboardFallbackRejectsImageObject() async throws {
        let pasteboard = VerificationPasteboard()
        defer { pasteboard.clearContents() }
        writePasteboard(pasteboard, text: "original")

        let fallback = makeFallback(pasteboard: pasteboard) { _ in
            let item = NSPasteboardItem()
            item.setString("image label", forType: .string)
            item.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
            pasteboard.clearContents()
            _ = pasteboard.writeObjects([item])
            return true
        }

        do {
            let text = try await fallback.captureSelection(sourceProcessIdentifier: 42)
            throw OverlayStateVerificationError.failed(
                "图片对象的文字描述不得触发浮窗，实际返回：\(text)"
            )
        } catch let error as OverlayStateVerificationError {
            throw error
        } catch ClipboardSelectionFallbackError.nonTextContent {
            try expect(
                pasteboard.string(forType: .string) == "original",
                "拒绝图片对象后应恢复原剪贴板"
            )
        }
    }

    private static func verifyClipboardFallbackRejectsDynamicFileObject() async throws {
        let pasteboard = VerificationPasteboard()
        defer { pasteboard.clearContents() }
        writePasteboard(pasteboard, text: "original")

        let fallback = makeFallback(pasteboard: pasteboard) { _ in
            let item = NSPasteboardItem()
            item.setString("oh_modules", forType: .string)
            let observedDevEcoTypes = [
                "dyn.ah62d4rv4gu81k3p2su11n6xmfz0gw65y",
                "dyn.ah62d4rv4gu81uppxsbw0g4pbru10s5xtrzww425tsby0n3brq3y023px",
                "dyn.ah62d4rv4gu8y6y4grf0gn5xbrzw1gydcr7u1e3cytf2gn",
                "dyn.ah62d4rv4gu8yc6durvwwaznwmuuha2pxsvw0e55bsmwca7d3sbwu",
                "dyn.ah62d4rv4gu8zkvn2nu",
                "dyn.ah62d4rv4gu8znzcghbtzgzcwmfhes",
            ]
            for identifier in observedDevEcoTypes {
                item.setData(Data([0x01]), forType: .init(identifier))
            }
            pasteboard.clearContents()
            _ = pasteboard.writeObjects([item])
            return true
        }

        do {
            let text = try await fallback.captureSelection(sourceProcessIdentifier: 42)
            throw OverlayStateVerificationError.failed(
                "动态文件对象的纯文本表示不得触发浮窗，实际返回：\(text)"
            )
        } catch let error as OverlayStateVerificationError {
            throw error
        } catch ClipboardSelectionFallbackError.nonTextContent {
            try expect(
                pasteboard.string(forType: .string) == "original",
                "拒绝动态文件对象后应恢复原剪贴板"
            )
        }
    }

    private static func verifyClipboardFallbackAcceptsChromiumText() async throws {
        let pasteboard = VerificationPasteboard()
        defer { pasteboard.clearContents() }
        writePasteboard(pasteboard, text: "original")

        let fallback = makeFallback(pasteboard: pasteboard) { _ in
            let item = NSPasteboardItem()
            item.setString("selected text", forType: .string)
            item.setString("<p>selected text</p>", forType: .html)
            item.setData(
                Data([0x01]),
                forType: .init("org.chromium.internal.source-rfh-token")
            )
            item.setString(
                "https://example.test/",
                forType: .init("org.chromium.source-url")
            )
            pasteboard.clearContents()
            _ = pasteboard.writeObjects([item])
            return true
        }

        let text = try await fallback.captureSelection(sourceProcessIdentifier: 42)
        try expect(text == "selected text", "Chromium 真文字选区应继续支持复制回退")
        try expect(
            pasteboard.string(forType: .string) == "original",
            "读取 Chromium 真文字后应恢复原剪贴板"
        )
    }

    private static func throwIfReached(_ message: String) -> Bool {
        assertionFailure(message)
        return false
    }

    private static func makeFallback(
        pasteboard: VerificationPasteboard,
        timeout: Duration = .milliseconds(100),
        stabilityDelay: Duration = .milliseconds(1),
        sendCopy: @escaping ClipboardSelectionFallback.CopyAction
    ) -> ClipboardSelectionFallback {
        ClipboardSelectionFallback(
            pasteboard: pasteboard,
            timeout: timeout,
            pollInterval: .milliseconds(1),
            stabilityDelay: stabilityDelay,
            sendCopy: sendCopy,
            isSourceFrontmost: { _ in true }
        )
    }

    private static func writePasteboard(
        _ pasteboard: VerificationPasteboard,
        text: String,
        rtf: Data? = nil
    ) {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if let rtf {
            item.setData(rtf, forType: .rtf)
        }
        pasteboard.clearContents()
        _ = pasteboard.writeObjects([item])
    }

    private static func verifyPointerSelectionGesture() throws {
        var gesture = PointerSelectionGesture()

        gesture.begin(at: .zero)
        try expect(
            gesture.end(at: CGPoint(x: 1, y: 1), clickCount: 1) == nil,
            "普通单击不得触发旧高亮选区"
        )

        gesture.begin(at: .zero)
        gesture.update(at: CGPoint(x: 8, y: 0))
        let dragIntent = gesture.end(at: CGPoint(x: 10, y: 0), clickCount: 1)
        try expect(
            dragIntent == .drag,
            "达到阈值的拖选应触发取词"
        )
        try expect(dragIntent?.fallbackPolicy == .enabled, "拖选应允许复制回退")

        gesture.begin(at: .zero)
        let multiClickIntent = gesture.end(at: .zero, clickCount: 2)
        try expect(
            multiClickIntent == .multiClick,
            "双击选词应触发取词"
        )
        try expect(
            multiClickIntent?.fallbackPolicy == .textHitRequired,
            "双击 AX 无文字时必须先验证鼠标命中的是文本表面"
        )

        gesture.begin(at: .zero)
        gesture.update(at: CGPoint(x: 8, y: 0))
        let movedMultiClickIntent = gesture.end(at: CGPoint(x: 8, y: 0), clickCount: 2)
        try expect(
            movedMultiClickIntent == .multiClick,
            "多击伴随轻微移动时仍应保持 multiClick 意图"
        )
        try expect(
            movedMultiClickIntent?.fallbackPolicy == .textHitRequired,
            "多击伴随轻微移动时仍应要求文本命中证据"
        )

        gesture.begin(at: .zero)
        let shiftClickIntent = gesture.end(at: .zero, clickCount: 1, isShiftPressed: true)
        try expect(
            shiftClickIntent == .shiftClick,
            "Shift-click 扩展选区应触发取词"
        )
        try expect(
            shiftClickIntent?.fallbackPolicy == .disabled,
            "Shift-click AX 无文字时不得复制列表项"
        )

        gesture.begin(at: .zero)
        gesture.update(at: CGPoint(x: 2, y: 1))
        try expect(
            gesture.end(at: CGPoint(x: 3, y: 1), clickCount: 1) == nil,
            "阈值内的轻微移动仍应视为普通单击"
        )
    }

    private static func verifySelectionHitClassifier() throws {
        let codexTextPath = [
            SelectionHitEvidenceNode(role: "AXScrollArea", actions: [], attributes: []),
            SelectionHitEvidenceNode(
                role: "AXGroup",
                actions: [],
                attributes: [
                    "AXNumberOfCharacters",
                    "AXSelectedText",
                    "AXSelectedTextRange",
                    "AXVisibleCharacterRange",
                ]
            ),
        ]
        try expect(
            SelectionHitClassifier.supportsTextSelection(in: codexTextPath),
            "Codex 正文命中链应允许多击复制回退"
        )

        let vscodeTextPath = [
            SelectionHitEvidenceNode(
                role: "AXGroup",
                actions: ["AXScrollToVisible", "AXShowMenu"],
                attributes: [
                    "AXNumberOfCharacters",
                    "AXSelectedText",
                    "AXSelectedTextMarkerRange",
                    "AXSelectedTextRange",
                    "AXVisibleCharacterRange",
                ]
            ),
            SelectionHitEvidenceNode(
                role: "AXGroup",
                actions: ["AXScrollToVisible", "AXShowMenu"],
                attributes: ["AXSelectedText", "AXSelectedTextRange"]
            ),
        ]
        try expect(
            SelectionHitClassifier.supportsTextSelection(in: vscodeTextPath),
            "VSCode 正文的 AXShowMenu 不应覆盖其真实选区语义"
        )

        let ideFileTreePath = [
            SelectionHitEvidenceNode(
                role: "AXStaticText",
                actions: ["AXPress", "AXShowMenu"],
                attributes: ["AXValue", "AXVisibleCharacterRange"]
            ),
            SelectionHitEvidenceNode(role: "AXOutline", actions: [], attributes: ["AXValue"]),
        ]
        try expect(
            !SelectionHitClassifier.supportsTextSelection(in: ideFileTreePath),
            "带 Press/ShowMenu 动作的 IDE 文件树节点不得进入多击复制回退"
        )

        let ideTabPath = [
            SelectionHitEvidenceNode(
                role: "AXStaticText",
                actions: [],
                attributes: ["AXValue", "AXVisibleCharacterRange"]
            ),
            SelectionHitEvidenceNode(role: "AXWindow", actions: ["AXRaise"], attributes: []),
        ]
        try expect(
            !SelectionHitClassifier.supportsTextSelection(in: ideTabPath),
            "无选区能力的 IDE Tab 不得复制焦点编辑器里的残留选区"
        )

        let vscodeTreePath = [
            vscodeTextPath[0],
            vscodeTextPath[1],
            SelectionHitEvidenceNode(
                role: "AXRow",
                actions: ["AXScrollToVisible", "AXShowMenu"],
                attributes: ["AXSelectedText", "AXSelectedTextRange"]
            ),
            SelectionHitEvidenceNode(
                role: "AXOutline",
                actions: ["AXShowMenu"],
                attributes: ["AXSelectedText", "AXSelectedTextRange"]
            ),
        ]
        try expect(
            !SelectionHitClassifier.supportsTextSelection(in: vscodeTreePath),
            "VSCode 对象路径前层即使像文本，深层 AXRow 仍必须否决回退"
        )

        let buttonInsideTextSurface = [
            SelectionHitEvidenceNode(
                role: "AXButton",
                actions: ["AXPress"],
                attributes: ["AXValue"]
            ),
            codexTextPath[1],
        ]
        try expect(
            !SelectionHitClassifier.supportsTextSelection(in: buttonInsideTextSurface),
            "文本容器内的可操作控件也不得借用祖先选区进入回退"
        )
    }

    private static func verifyPlacement() throws {
        let visible = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let size = CGSize(width: 200, height: 120)

        let below = OverlayPlacement.calculate(
            anchor: CGRect(x: 600, y: 400, width: 20, height: 20),
            panelSize: size,
            visibleFrame: visible
        )
        try expect(below.origin == CGPoint(x: 510, y: 272), "空间足够时应显示在选区下方")

        let above = OverlayPlacement.calculate(
            anchor: CGRect(x: 600, y: 20, width: 20, height: 20),
            panelSize: size,
            visibleFrame: visible
        )
        try expect(above.origin == CGPoint(x: 510, y: 48), "下方空间不足时应显示在选区上方")

        let expandedBelow = OverlayPlacement.resizedFrame(
            anchoredTopLeft: CGPoint(x: below.minX, y: below.maxY),
            panelSize: CGSize(width: 200, height: 240),
            visibleFrame: visible
        )
        try expect(expandedBelow.maxY == below.maxY, "选区下方的浮层展开时应保持上边缘不动")

        let collapsedBelow = OverlayPlacement.resizedFrame(
            anchoredTopLeft: CGPoint(x: below.minX, y: below.maxY),
            panelSize: CGSize(width: size.width, height: OverlayPlacement.minimumPanelHeight),
            visibleFrame: visible
        )
        try expect(collapsedBelow.maxY == below.maxY, "浮层展开后再收缩仍应回到同一上边缘")
        try expect(
            collapsedBelow.height == OverlayPlacement.minimumPanelHeight,
            "收缩高度必须与 36pt 操作栏一致，不能产生垂直居中的 2pt 位移"
        )

        let expandedAbove = OverlayPlacement.resizedFrame(
            anchoredTopLeft: CGPoint(x: above.minX, y: above.maxY),
            panelSize: CGSize(width: 200, height: 240),
            visibleFrame: visible
        )
        try expect(expandedAbove.maxY == above.maxY, "选区上方的浮层展开时也应保持上边缘不动")

        let constrainedAtBottom = OverlayPlacement.resizedFrame(
            anchoredTopLeft: CGPoint(x: below.minX, y: 100),
            panelSize: CGSize(width: 200, height: 240),
            visibleFrame: visible
        )
        try expect(constrainedAtBottom.maxY == 100, "屏幕底部空间不足时仍应保持上边缘不动")
        try expect(constrainedAtBottom.minY == 10, "屏幕底部空间不足时应限制窗口高度而不是越界")

        let secondary = CGRect(x: -1_280, y: -120, width: 1_280, height: 800)
        let clamped = OverlayPlacement.calculate(
            anchor: CGRect(x: -1_400, y: -100, width: 20, height: 20),
            panelSize: size,
            visibleFrame: secondary
        )
        try expect(
            clamped.minX >= secondary.minX + OverlayPlacement.edgeInset
                && clamped.maxX <= secondary.maxX - OverlayPlacement.edgeInset
                && clamped.minY >= secondary.minY + OverlayPlacement.edgeInset
                && clamped.maxY <= secondary.maxY - OverlayPlacement.edgeInset,
            "负坐标副屏上的浮层应完整留在可见区域"
        )
    }

    private static func verifyEmptyPinnedPersistence() throws {
        let suite = "ClipAll.OverlayVerification.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw OverlayStateVerificationError.failed("无法创建隔离 UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let initial = SettingsStore(defaults: defaults)
        try expect(initial.pinnedCapabilityIDs == [.search, .translate], "首次启动应固定搜索和翻译")
        _ = initial.setPinned(.search, isPinned: false)
        _ = initial.setPinned(.translate, isPinned: false)
        try expect(initial.pinnedCapabilityIDs.isEmpty, "用户应能取消全部固定能力")

        let reloaded = SettingsStore(defaults: defaults)
        try expect(reloaded.pinnedCapabilityIDs.isEmpty, "空固定列表重启后不应恢复默认值")
        try expect(reloaded.isSelectionFallbackEnabled, "兼容取词首次启动应默认开启")

        reloaded.isSelectionFallbackEnabled = false
        reloaded.setSelectionFallbackExcluded("com.example.Editor", isExcluded: true)
        let fallbackReloaded = SettingsStore(defaults: defaults)
        try expect(!fallbackReloaded.isSelectionFallbackEnabled, "兼容取词开关应持久化")
        try expect(
            !fallbackReloaded.allowsSelectionFallback(for: "com.example.Editor"),
            "排除应用不应进入复制回退"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw OverlayStateVerificationError.failed(message) }
    }
}

@MainActor
private final class VerificationPasteboard: ClipboardPasteboard {
    private(set) var changeCount = 0
    private(set) var pasteboardItems: [NSPasteboardItem]? = []

    @discardableResult
    func clearContents() -> Int {
        pasteboardItems = []
        changeCount += 1
        return changeCount
    }

    func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
        pasteboardItems?.lazy.compactMap { $0.string(forType: dataType) }.first
    }

    func data(forType dataType: NSPasteboard.PasteboardType) -> Data? {
        pasteboardItems?.lazy.compactMap { $0.data(forType: dataType) }.first
    }

    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool {
        let items = objects.compactMap { $0 as? NSPasteboardItem }
        guard items.count == objects.count else { return false }
        pasteboardItems = items
        changeCount += 1
        return true
    }
}
