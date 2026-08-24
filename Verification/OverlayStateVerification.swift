import AppKit
import Carbon.HIToolbox
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
        try verifyCarbonHotKeyIdentity()
        try verifyPointerSelectionGesture()
        try verifySelectionAutomaticDisplayPolicies()
        try await verifySelectionMonitorPolicyGate()
        try await verifySelectionMonitorMultiClickPreflight()
        try verifySelectionHitClassifier()
        try verifyEmptyPinnedPersistence()
        try verifyApplicationEntryVisibilityPersistence()
        try await verifyClipboardSelectionFallback()
        print("Overlay state verification passed")
    }

    private static func verifyCarbonHotKeyIdentity() throws {
        let expectedSignature: OSType = 0x434C_4F56
        let expectedIdentifier: UInt32 = 1
        var event: EventRef?
        let createStatus = CreateEvent(
            nil,
            OSType(kEventClassKeyboard),
            UInt32(kEventHotKeyPressed),
            GetCurrentEventTime(),
            EventAttributes(kEventAttributeNone),
            &event
        )
        guard createStatus == noErr, let event else {
            throw OverlayStateVerificationError.failed("无法创建 Carbon 热键验证事件")
        }
        defer { ReleaseEvent(event) }

        var identifier = EventHotKeyID(
            signature: expectedSignature,
            id: expectedIdentifier
        )
        let setStatus = SetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            MemoryLayout<EventHotKeyID>.size,
            &identifier
        )
        guard setStatus == noErr else {
            throw OverlayStateVerificationError.failed("无法写入 Carbon 热键验证 ID")
        }

        try expect(
            matchesClipAllHotKeyEvent(
                event,
                signature: expectedSignature,
                identifier: expectedIdentifier
            ),
            "Carbon 热键应只匹配自己的 signature 与 identifier"
        )
        try expect(
            !matchesClipAllHotKeyEvent(
                event,
                signature: 0x434C_5041,
                identifier: expectedIdentifier
            ),
            "Esc 热键不能被取词快捷键处理器接收"
        )
    }

    private static func verifyClipboardSelectionFallback() async throws {
        try await verifyClipboardScenario("私有类型恢复", verifyClipboardFallbackRestoresPrivateFlavor)
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

    private static func verifyClipboardFallbackRestoresPrivateFlavor() async throws {
        _ = NSApplication.shared
        let name = NSPasteboard.Name("com.wxy.ClipAll.verification.\(UUID().uuidString)")
        let pasteboard = NSPasteboard(name: name)
        defer {
            pasteboard.clearContents()
            pasteboard.releaseGlobally()
        }

        var nativePasteboard: Pasteboard?
        guard PasteboardCreate(name.rawValue as CFString, &nativePasteboard) == noErr,
              let nativePasteboard,
              PasteboardClear(nativePasteboard) == noErr,
              let itemIdentifier = UnsafeMutableRawPointer(bitPattern: 1) else {
            throw OverlayStateVerificationError.failed("无法创建私有类型验证剪贴板")
        }

        let privateType = "com.trolltech.anymime.IMAGE_PATH"
        let originalData = Data([0x43, 0x6C, 0x69, 0x70, 0x41, 0x6C, 0x6C])
        guard PasteboardPutItemFlavor(
            nativePasteboard,
            itemIdentifier,
            privateType as CFString,
            originalData as CFData,
            []
        ) == noErr else {
            throw OverlayStateVerificationError.failed("无法写入私有类型验证数据")
        }

        let fallback = ClipboardSelectionFallback(
            pasteboard: pasteboard,
            timeout: .milliseconds(100),
            pollInterval: .milliseconds(1),
            stabilityDelay: .milliseconds(1),
            sendCopy: { _ in
                writePasteboard(pasteboard, text: "selected")
                return true
            },
            isSourceFrontmost: { _ in true }
        )
        let text = try await fallback.captureSelection(sourceProcessIdentifier: 42)
        try expect(text == "selected", "私有类型快照不应阻断本次取词")

        _ = PasteboardSynchronize(nativePasteboard)
        var restoredIdentifier: PasteboardItemID?
        guard PasteboardGetItemIdentifier(nativePasteboard, 1, &restoredIdentifier) == noErr,
              let restoredIdentifier else {
            throw OverlayStateVerificationError.failed("私有类型快照未恢复 item")
        }
        var restoredData: CFData?
        guard PasteboardCopyItemFlavorData(
            nativePasteboard,
            restoredIdentifier,
            privateType as CFString,
            &restoredData
        ) == noErr,
            restoredData as Data? == originalData else {
            throw OverlayStateVerificationError.failed("私有类型数据未按字节恢复")
        }
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
            pasteboard: pasteboard
        ) { _ in
            writePasteboard(pasteboard, text: "selected")
            return true
        }
        pasteboard.afterNextStringRead = {
            writePasteboard(pasteboard, text: "external")
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
        _ pasteboard: any ClipboardPasteboard,
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
        try expect(
            dragIntent?.fallbackPolicy == .compatiblePointer,
            "拖选应允许缺少 AX 文字语义的控件进入兼容复制回退"
        )

        gesture.begin(at: .zero)
        let multiClickIntent = gesture.end(at: .zero, clickCount: 2)
        try expect(
            multiClickIntent == .multiClick,
            "双击选词应触发取词"
        )
        try expect(
            multiClickIntent?.fallbackPolicy == .textHitRequired,
            "双击应只在命中路径提供文字证据时允许复制回退"
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
            "多击伴随轻微移动时仍应要求文字命中证据"
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

    private static func verifySelectionAutomaticDisplayPolicies() throws {
        let suite = "ClipAll.SelectionPolicyVerification.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw OverlayStateVerificationError.failed("无法创建取词策略 UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsStore(defaults: defaults)
        try expect(settings.isDragSelectionEnabled, "拖选默认应开启")
        try expect(settings.isMultiClickSelectionEnabled, "双击/多击默认应开启")
        try expect(
            settings.allowsAutomaticDisplay(for: .drag, bundleIdentifier: nil),
            "缺少 Bundle ID 时拖选应跟随全局默认"
        )
        try expect(
            settings.allowsAutomaticDisplay(for: .multiClick, bundleIdentifier: nil),
            "缺少 Bundle ID 时多击应跟随全局默认"
        )
        settings.isMultiClickSelectionEnabled = false
        try expect(
            !settings.allowsAutomaticDisplay(
                for: .multiClick,
                bundleIdentifier: "com.example.Global"
            ),
            "关闭全局多击后跟随全局的 App 不应自动显示"
        )
        try expect(
            settings.allowsAutomaticDisplay(for: .drag, bundleIdentifier: "com.example.Global"),
            "关闭全局多击不应影响拖选"
        )

        settings.isDragSelectionEnabled = false
        try expect(
            !settings.allowsAutomaticDisplay(
                for: .shiftClick,
                bundleIdentifier: "com.example.Global"
            ),
            "关闭全局拖选后 Shift 扩选也不应自动显示"
        )

        settings.setAutomaticDisplayPolicy(.dragOnly, for: "com.example.DragOnly")
        try expect(
            settings.allowsAutomaticDisplay(
                for: .drag,
                bundleIdentifier: "com.example.DragOnly"
            ),
            "仅拖选应覆盖关闭的全局拖选规则"
        )
        try expect(
            !settings.allowsAutomaticDisplay(
                for: .multiClick,
                bundleIdentifier: "com.example.DragOnly"
            ),
            "仅拖选 App 的多击不应自动显示"
        )

        settings.setAutomaticDisplayPolicy(.disabled, for: "com.example.Disabled")
        try expect(
            !settings.allowsAutomaticDisplay(
                for: .drag,
                bundleIdentifier: "com.example.Disabled"
            ),
            "永不自动显示应拒绝拖选"
        )
        settings.setSelectionFallbackExcluded("com.example.Legacy", isExcluded: true)
        try expect(
            settings.selectionApplicationBundleIdentifiers == [
                "com.example.Disabled",
                "com.example.DragOnly",
                "com.example.Legacy",
            ],
            "应用列表应合并显示策略与旧兼容排除名单"
        )
        try expect(
            settings.automaticDisplayPolicy(for: "com.example.Legacy") == .followGlobal,
            "旧兼容排除不得升级为禁止自动显示"
        )

        let reloaded = SettingsStore(defaults: defaults)
        try expect(!reloaded.isDragSelectionEnabled, "拖选全局开关应持久化")
        try expect(!reloaded.isMultiClickSelectionEnabled, "多击全局开关应持久化")
        try expect(
            reloaded.automaticDisplayPolicy(for: "com.example.DragOnly") == .dragOnly,
            "应用自动显示策略应持久化"
        )

        reloaded.removeSelectionApplication("com.example.Legacy")
        try expect(
            !reloaded.selectionApplicationBundleIdentifiers.contains("com.example.Legacy"),
            "删除应用规则应移除旧兼容排除记录"
        )
        try expect(
            reloaded.allowsSelectionFallback(for: "com.example.Legacy"),
            "删除应用规则后兼容取词应恢复全局默认"
        )

        let invalidPayload = [
            "": SelectionAutomaticDisplayPolicy.disabled.rawValue,
            "com.example.Valid": SelectionAutomaticDisplayPolicy.dragOnly.rawValue,
            "com.example.Invalid": "futurePolicy",
        ]
        defaults.set(
            try JSONEncoder().encode(invalidPayload),
            forKey: "selectionAutomaticDisplayPolicies.v1"
        )
        let sanitized = SettingsStore(defaults: defaults)
        try expect(
            sanitized.selectionApplicationBundleIdentifiers.contains("com.example.Valid"),
            "合法持久化策略应保留"
        )
        try expect(
            !sanitized.selectionApplicationBundleIdentifiers.contains("com.example.Invalid"),
            "未知持久化策略应忽略"
        )

        defaults.set(
            ["  ", " com.example.Trimmed ", Bundle.main.bundleIdentifier ?? ""],
            forKey: "selectionFallbackExcludedBundleIdentifiers.v1"
        )
        let sanitizedFallback = SettingsStore(defaults: defaults)
        try expect(
            sanitizedFallback.selectionFallbackExcludedBundleIdentifiers
                == ["com.example.Trimmed"],
            "兼容取词排除名单应忽略空值、自身并清理空白"
        )
    }

    private static func verifySelectionMonitorPolicyGate() async throws {
        let capture = VerificationSelectionCapture()
        let bundleSource = VerificationBundleSource(value: "com.example.Blocked")
        capture.sourceBundleIdentifier = bundleSource.value
        var policyCallCount = 0
        var invalidationCount = 0
        var selectionCount = 0
        let monitor = SelectionMonitor(
            captureService: capture,
            shortcut: .standard,
            allowsAutomaticDisplay: { _, bundleIdentifier in
                policyCallCount += 1
                return bundleIdentifier != "com.example.Blocked"
            },
            frontmostBundleIdentifier: { bundleSource.value },
            onSelection: { _ in selectionCount += 1 },
            onSelectionInvalidated: { invalidationCount += 1 }
        )

        monitor.capturePointerSelection(
            .multiClick,
            sourceBundleIdentifier: bundleSource.value,
            after: .zero,
            requiresRunning: false
        )
        try expect(capture.callCount == 0, "禁用 App 必须在捕获前被拒绝")
        try expect(invalidationCount == 1, "拒绝自动显示时应关闭旧浮窗")

        bundleSource.value = "com.example.Allowed"
        capture.sourceBundleIdentifier = bundleSource.value
        monitor.capturePointerSelection(
            .multiClick,
            sourceBundleIdentifier: bundleSource.value,
            after: .zero,
            requiresRunning: false
        )
        try await waitUntil("允许的多击未触发捕获") { capture.callCount == 1 }
        try expect(
            capture.fallbackPolicies == [.textHitRequired],
            "多击通过门禁后必须保留严格的文字命中策略"
        )
        try expect(selectionCount == 1, "允许的自动捕获应发布一次选区")

        bundleSource.value = "com.example.BeforeSwitch"
        capture.sourceBundleIdentifier = bundleSource.value
        monitor.capturePointerSelection(
            .drag,
            sourceBundleIdentifier: bundleSource.value,
            after: .milliseconds(25),
            requiresRunning: false
        )
        bundleSource.value = "com.example.AfterSwitch"
        capture.sourceBundleIdentifier = bundleSource.value
        try await waitUntil("来源 App 切换后未使旧选区失效") { invalidationCount == 2 }
        try expect(capture.callCount == 1, "来源 App 切换后不得读取新前台 App")

        let pointerPolicyCalls = policyCallCount
        capture.sourceBundleIdentifier = bundleSource.value
        monitor.captureNow()
        try await waitUntil("菜单主动取词未绕过自动策略") { capture.callCount == 2 }
        monitor.handleRegisteredHotKey(requiresRunning: false)
        try await waitUntil("全局快捷键未绕过自动策略") { capture.callCount == 3 }
        try expect(
            policyCallCount == pointerPolicyCalls,
            "菜单和快捷键不得调用鼠标自动显示策略"
        )

        let selectionCountBeforeBoundedSelection = selectionCount
        capture.selectionBounds = CGRect(
            x: -1_000_000,
            y: -1_000_000,
            width: 2_000_000,
            height: 2_000_000
        )
        monitor.capturePointerSelection(
            .multiClick,
            sourceBundleIdentifier: bundleSource.value,
            after: .zero,
            requiresRunning: false
        )
        try await waitUntil("命中范围的 AX 选区未被捕获") { capture.callCount == 4 }
        try expect(
            selectionCount == selectionCountBeforeBoundedSelection + 1,
            "双击点命中 AX 选区范围时仍应发布选区"
        )

        let selectionCountBeforeStaleSelection = selectionCount
        let invalidationCountBeforeStaleSelection = invalidationCount
        capture.selectionBounds = CGRect(
            x: 1_000_000,
            y: 1_000_000,
            width: 20,
            height: 20
        )
        monitor.capturePointerSelection(
            .multiClick,
            sourceBundleIdentifier: bundleSource.value,
            after: .zero,
            requiresRunning: false
        )
        try await waitUntil("残留 AX 选区未进入发布门禁") { capture.callCount == 5 }
        try expect(
            selectionCount == selectionCountBeforeStaleSelection,
            "双击点未命中 AX 选区范围时不得发布残留选区"
        )
        try expect(
            invalidationCount == invalidationCountBeforeStaleSelection + 1,
            "拒绝残留 AX 选区时应关闭旧浮窗"
        )
    }

    private static func verifySelectionMonitorMultiClickPreflight() async throws {
        let capture = VerificationSelectionCapture()
        capture.sourceBundleIdentifier = "com.example.qt.opaque-text"
        let monitor = SelectionMonitor(
            captureService: capture,
            shortcut: .standard,
            frontmostBundleIdentifier: { capture.sourceBundleIdentifier },
            onSelection: { _ in }
        )

        capture.preflightPolicy = .compatiblePointer
        monitor.handlePointerDown(at: .zero, clickCount: 2)
        monitor.handlePointerUp(
            at: .zero,
            clickCount: 2,
            isShiftPressed: false,
            requiresRunning: false
        )
        try await waitUntil("文字目标的双击预检未触发捕获") { capture.callCount == 1 }
        try expect(
            capture.fallbackPolicies == [.compatiblePointer],
            "第二次按下命中文字候应沿用兼容回退"
        )

        capture.preflightPolicy = .textHitRequired
        monitor.handlePointerDown(at: .zero, clickCount: 2)
        monitor.handlePointerUp(
            at: .zero,
            clickCount: 2,
            isShiftPressed: false,
            requiresRunning: false
        )
        try await waitUntil("图片目标的双击预检未触发捕获") { capture.callCount == 2 }
        try expect(
            capture.fallbackPolicies.last == .textHitRequired,
            "第二次按下命中图片时必须在复制前保持严格门禁"
        )

        monitor.handlePointerDown(at: .zero, clickCount: 1)
        monitor.handlePointerUp(
            at: .zero,
            clickCount: 2,
            isShiftPressed: false,
            requiresRunning: false
        )
        try await waitUntil("缺失预检的双击未触发捕获") { capture.callCount == 3 }
        try expect(
            capture.fallbackPolicies.last == .textHitRequired,
            "缺少第二次按下预检时必须安全回退到严格门禁"
        )
        try expect(capture.preflightCallCount == 2, "只应预检双击或多击的按下事件")
    }

    private static func waitUntil(
        _ failureMessage: String,
        condition: @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .milliseconds(500)
        while !condition() {
            guard clock.now < deadline else {
                throw OverlayStateVerificationError.failed(failureMessage)
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private static func verifySelectionHitClassifier() throws {
        try expect(
            SelectionHitClassifier.multiClickFallbackPolicy(
                in: [],
                hasTextSelectionCursor: true
            ) == .compatiblePointer,
            "AX 命中链为空但系统显示文字光标时，双击应进入内容校验回退"
        )
        try expect(
            SelectionHitClassifier.multiClickFallbackPolicy(
                in: [],
                hasTextSelectionCursor: false
            ) == .textHitRequired,
            "AX 命中链为空且系统不是文字光标时，双击必须保持严格门禁"
        )
        try expect(
            !SelectionHitClassifier.allowsClipboardFallback(
                in: [],
                policy: .textHitRequired
            ),
            "自动指针取词的 AX 命中链为空时不得发送复制快捷键"
        )
        try expect(
            SelectionHitClassifier.allowsClipboardFallback(
                in: [],
                policy: .compatiblePointer
            ),
            "明确拖选在 AX 命中链为空时应进入内容校验回退"
        )

        let customTextPath = [
            SelectionHitEvidenceNode(role: "AXGroup", actions: [], attributes: []),
            SelectionHitEvidenceNode(role: "AXWindow", actions: ["AXRaise"], attributes: []),
        ]
        try expect(
            SelectionHitClassifier.allowsClipboardFallback(
                in: customTextPath,
                policy: .compatiblePointer
            ),
            "Qt/QML 自定义文字控件应通过拖选兼容门禁"
        )

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
            SelectionHitClassifier.allowsClipboardFallback(in: codexTextPath),
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
            SelectionHitClassifier.allowsClipboardFallback(in: vscodeTextPath),
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
            !SelectionHitClassifier.allowsClipboardFallback(in: ideFileTreePath),
            "带 Press/ShowMenu 动作的 IDE 文件树节点不得进入多击复制回退"
        )
        try expect(
            !SelectionHitClassifier.allowsClipboardFallback(
                in: ideFileTreePath,
                policy: .compatiblePointer
            ),
            "带 Press 动作的文件树节点不得进入拖选兼容回退"
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
            !SelectionHitClassifier.allowsClipboardFallback(in: ideTabPath),
            "无选区能力的 IDE Tab 不得复制焦点编辑器里的残留选区"
        )

        let explicitTabPath = [
            SelectionHitEvidenceNode(
                role: "AXTabButton",
                actions: ["AXPress"],
                attributes: ["AXValue"]
            ),
            SelectionHitEvidenceNode(role: "AXTabGroup", actions: [], attributes: []),
        ]
        try expect(
            !SelectionHitClassifier.allowsClipboardFallback(
                in: explicitTabPath,
                policy: .compatiblePointer
            ),
            "明确的 Tab 控件不得借拖选兼容策略进入复制回退"
        )

        let imagePath = [
            SelectionHitEvidenceNode(
                role: "AXImage",
                actions: [],
                attributes: ["AXDescription"]
            ),
            SelectionHitEvidenceNode(role: "AXGroup", actions: [], attributes: []),
        ]
        try expect(
            !SelectionHitClassifier.allowsClipboardFallback(in: imagePath),
            "图片目标必须在发送复制快捷键前被拒绝"
        )
        try expect(
            !SelectionHitClassifier.allowsClipboardFallback(
                in: imagePath,
                policy: .compatiblePointer
            ),
            "图片目标不得借拖选兼容策略发送复制快捷键"
        )
        try expect(
            SelectionHitClassifier.multiClickFallbackPolicy(
                in: imagePath,
                hasTextSelectionCursor: true
            ) == .textHitRequired,
            "AX 已明确识别为图片时，即使光标异常也必须保持严格门禁"
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
            !SelectionHitClassifier.allowsClipboardFallback(in: vscodeTreePath),
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
            !SelectionHitClassifier.allowsClipboardFallback(in: buttonInsideTextSurface),
            "文本容器内的可操作控件也不得借用祖先选区进入回退"
        )
        try expect(
            !SelectionHitClassifier.allowsClipboardFallback(
                in: buttonInsideTextSurface,
                policy: .compatiblePointer
            ),
            "按钮不得借拖选兼容策略进入复制回退"
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
        try expect(initial.setPinned(.timestampToDate, isPinned: true), "未满四个时应允许固定插件能力")
        try expect(initial.setPinned(.dateToTimestamp, isPinned: true), "第四个插件能力应能固定")

        let overflowCapability: CapabilityID = "verification.extra-capability"
        try expect(
            !initial.setPinned(overflowCapability, isPinned: true),
            "固定能力达到四个后应拒绝继续添加"
        )
        try expect(
            initial.pinnedCapabilityIDs.count == SettingsStore.maximumPinnedCapabilities,
            "拒绝第五个能力后固定列表不应改变"
        )

        try expect(initial.setPinned(.search, isPinned: false), "已固定能力应能取消")
        try expect(
            initial.setPinned(overflowCapability, isPinned: true),
            "取消固定后应能从插件重新固定其他能力"
        )

        for id in initial.pinnedCapabilityIDs {
            _ = initial.setPinned(id, isPinned: false)
        }
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

    private static func verifyApplicationEntryVisibilityPersistence() throws {
        let suite = "ClipAll.EntryVisibilityVerification.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw OverlayStateVerificationError.failed("无法创建入口可见性 UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let initial = SettingsStore(defaults: defaults)
        try expect(initial.appearancePreference == .system, "外观首次启动应跟随系统")
        try expect(initial.isMenuBarIconVisible, "菜单栏图标首次启动应默认显示")
        try expect(initial.isDockIconVisible, "Dock 图标首次启动应默认显示")

        try expect(initial.setDockIconVisible(false), "两个入口均显示时应允许隐藏 Dock")
        try expect(
            !initial.setMenuBarIconVisible(false),
            "只剩菜单栏入口时不得继续隐藏菜单栏"
        )
        try expect(initial.isMenuBarIconVisible, "拒绝隐藏最后入口后状态应保持不变")

        try expect(initial.setDockIconVisible(true), "应允许恢复 Dock 图标")
        try expect(initial.setMenuBarIconVisible(false), "Dock 显示时应允许隐藏菜单栏")
        initial.appearancePreference = .dark

        let reloaded = SettingsStore(defaults: defaults)
        try expect(reloaded.appearancePreference == .dark, "外观设置应持久化")
        try expect(!reloaded.isMenuBarIconVisible, "菜单栏图标设置应持久化")
        try expect(reloaded.isDockIconVisible, "Dock 图标设置应持久化")

        defaults.set(false, forKey: "menuBarIconVisible")
        defaults.set(false, forKey: "dockIconVisible")
        let repaired = SettingsStore(defaults: defaults)
        try expect(
            repaired.isMenuBarIconVisible || repaired.isDockIconVisible,
            "损坏设置也必须自动恢复至少一个入口"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw OverlayStateVerificationError.failed(message) }
    }
}

@MainActor
private final class VerificationBundleSource {
    var value: String?

    init(value: String?) {
        self.value = value
    }
}

@MainActor
private final class VerificationSelectionCapture: SelectionCapturing {
    private(set) var callCount = 0
    private(set) var fallbackPolicies: [SelectionFallbackPolicy] = []
    private(set) var preflightCallCount = 0
    var preflightPolicy = SelectionFallbackPolicy.textHitRequired
    var sourceBundleIdentifier: String?
    var selectionBounds: CGRect?

    func preflightFallbackPolicy(
        for intent: PointerSelectionIntent,
        at triggerLocation: CGPoint
    ) -> SelectionFallbackPolicy {
        preflightCallCount += 1
        return preflightPolicy
    }

    func captureCurrentSelection(
        triggerLocation: CGPoint,
        fallbackPolicy: SelectionFallbackPolicy
    ) async throws -> SelectionContext {
        callCount += 1
        fallbackPolicies.append(fallbackPolicy)
        return SelectionContext(
            text: "selected",
            sourceBundleIdentifier: sourceBundleIdentifier,
            selectionBounds: selectionBounds,
            triggerLocation: triggerLocation
        )!
    }
}

@MainActor
private final class VerificationPasteboard: ClipboardPasteboard {
    private(set) var changeCount = 0
    private(set) var pasteboardItems: [NSPasteboardItem]? = []
    var afterNextStringRead: (() -> Void)?

    @discardableResult
    func clearContents() -> Int {
        pasteboardItems = []
        changeCount += 1
        return changeCount
    }

    func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
        let value = pasteboardItems?.lazy.compactMap { $0.string(forType: dataType) }.first
        let action = afterNextStringRead
        afterNextStringRead = nil
        action?()
        return value
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
