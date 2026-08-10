import AppKit
import ApplicationServices
import Foundation
import OSLog

enum SelectionCaptureError: Error, LocalizedError, Equatable, Sendable {
    case permissionRequired
    case noFocusedElement
    case noSelection
    case unsupported
    case secureInput
    case sourceUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            "需要辅助功能权限才能读取选中文字"
        case .noFocusedElement:
            "当前应用没有可读取的焦点元素"
        case .noSelection:
            "当前没有有效的文字选区"
        case .unsupported:
            "当前应用不提供选中文字"
        case .secureInput:
            "安全输入框不允许读取"
        case .sourceUnavailable:
            "来源应用暂时无法响应"
        }
    }
}

@MainActor
protocol SelectionCapturing: AnyObject {
    func captureCurrentSelection(triggerLocation: CGPoint) async throws -> SelectionContext
}

@MainActor
final class SelectionCaptureService: SelectionCapturing {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.wxy.ClipAll",
        category: "SelectionCapture"
    )

    private struct CapturedSelection {
        let text: String
        let bounds: CGRect?
    }

    private let systemWideElement: AXUIElement
    private let clipboardFallback: ClipboardSelectionFallback
    private let isFallbackAllowed: @MainActor (String?) -> Bool

    init(
        systemWideElement: AXUIElement = AXUIElementCreateSystemWide(),
        clipboardFallback: ClipboardSelectionFallback = ClipboardSelectionFallback(),
        isFallbackAllowed: @escaping @MainActor (String?) -> Bool = { _ in false }
    ) {
        self.systemWideElement = systemWideElement
        self.clipboardFallback = clipboardFallback
        self.isFallbackAllowed = isFallbackAllowed
    }

    func captureCurrentSelection(
        triggerLocation: CGPoint = NSEvent.mouseLocation
    ) async throws -> SelectionContext {
        guard AXIsProcessTrusted() else {
            throw SelectionCaptureError.permissionRequired
        }

        let source = NSWorkspace.shared.frontmostApplication

        if let sourceBundleIdentifier = source?.bundleIdentifier,
           let ownBundleIdentifier = Bundle.main.bundleIdentifier,
           sourceBundleIdentifier == ownBundleIdentifier {
            throw SelectionCaptureError.noSelection
        }

        let selection: CapturedSelection
        do {
            selection = try capturedSelection(
                triggerLocation: triggerLocation,
                sourceApplication: source
            )
        } catch let error as SelectionCaptureError {
            guard error.allowsClipboardFallback,
                  let source,
                  isFallbackAllowed(source.bundleIdentifier) else {
                throw error
            }

            Self.logger.debug(
                "AX selection unavailable; trying clipboard fallback for bundle=\(source.bundleIdentifier ?? "unknown", privacy: .public)"
            )
            do {
                let text = try await clipboardFallback.captureSelection(
                    sourceProcessIdentifier: source.processIdentifier
                )
                selection = CapturedSelection(text: text, bounds: nil)
            } catch is CancellationError {
                throw CancellationError()
            } catch let fallbackError as ClipboardSelectionFallbackError {
                Self.logger.debug(
                    "Clipboard fallback ended: error=\(String(describing: fallbackError), privacy: .public)"
                )
                throw fallbackError.selectionCaptureError
            }
        }

        guard let context = SelectionContext(
            text: selection.text,
            sourceBundleIdentifier: source?.bundleIdentifier,
            sourceApplicationName: source?.localizedName,
            selectionBounds: selection.bounds,
            triggerLocation: triggerLocation
        ) else {
            throw SelectionCaptureError.noSelection
        }
        return context
    }

    private func focusedUIElement() throws -> AXUIElement {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard error == .success else { throw map(error) }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw SelectionCaptureError.noFocusedElement
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func focusedUIElement(in root: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            root,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func capturedSelection(
        triggerLocation: CGPoint,
        sourceApplication: NSRunningApplication?
    ) throws -> CapturedSelection {
        var candidates: [AXUIElement] = []

        if let focused = try? focusedUIElement() {
            appendUnique(focused, to: &candidates)
        }

        if let sourceApplication {
            let applicationElement = AXUIElementCreateApplication(sourceApplication.processIdentifier)
            if let focused = focusedUIElement(in: applicationElement) {
                appendUnique(focused, to: &candidates)
            }
        }

        if let hitElement = element(at: triggerLocation) {
            appendUnique(hitElement, to: &candidates)
        }

        guard !candidates.isEmpty else {
            throw SelectionCaptureError.noFocusedElement
        }

        var finalError = SelectionCaptureError.unsupported
        for candidate in candidates {
            do {
                return try capturedSelection(startingAt: candidate)
            } catch let error as SelectionCaptureError {
                if error == .secureInput {
                    throw error
                } else if error == .noSelection {
                    finalError = .noSelection
                }
            }
        }

        throw finalError
    }

    private func appendUnique(_ element: AXUIElement, to elements: inout [AXUIElement]) {
        guard !elements.contains(where: { CFEqual($0, element) }) else { return }
        elements.append(element)
    }

    private func element(at appKitPoint: CGPoint) -> AXUIElement? {
        let accessibilityPoint = accessibilityPoint(fromAppKitPoint: appKitPoint)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(accessibilityPoint.x),
            Float(accessibilityPoint.y),
            &element
        ) == .success else { return nil }
        return element
    }

    private func capturedSelection(startingAt focusedElement: AXUIElement) throws -> CapturedSelection {
        var candidate: AXUIElement? = focusedElement
        var finalError = SelectionCaptureError.unsupported

        // Web views and custom text controls often expose the active selection
        // on an ancestor (for example AXWebArea) rather than the focused child.
        // Keep traversal bounded so a malformed accessibility tree cannot stall
        // the main actor.
        for depth in 0..<32 {
            guard let element = candidate else { break }
            if isSecureTextElement(element) {
                throw SelectionCaptureError.secureInput
            }
            let selectedRange = selectedTextRange(in: element)
            let markerRange = selectedTextMarkerRange(in: element)

            do {
                let text = try selectedText(
                    in: element,
                    selectedRange: selectedRange,
                    markerRange: markerRange
                )
                let bounds = markerRange.flatMap {
                    selectionBounds(forTextMarkerRange: $0, in: element)
                } ?? selectedRange.flatMap {
                    selectionBounds(for: $0, in: element)
                }
                Self.logger.debug(
                    "Selection source resolved: ancestorDepth=\(depth, privacy: .public), role=\(self.role(of: element), privacy: .public), markerRange=\(markerRange != nil, privacy: .public), hasBounds=\(bounds != nil, privacy: .public)"
                )
                return CapturedSelection(text: text, bounds: bounds)
            } catch let error as SelectionCaptureError {
                switch error {
                case .noSelection:
                    finalError = .noSelection
                case .unsupported:
                    break
                default:
                    finalError = error
                }
            }

            candidate = parent(of: element)
        }

        throw finalError
    }

    private func isSecureTextElement(_ element: AXUIElement) -> Bool {
        var subroleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSubroleAttribute as CFString,
            &subroleValue
        ) == .success,
        let subrole = subroleValue as? String
        else { return false }

        return subrole == kAXSecureTextFieldSubrole as String
    }

    private func selectedText(
        in element: AXUIElement,
        selectedRange: CFRange?,
        markerRange: CFTypeRef?
    ) throws -> String {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        )
        if error == .success, let text = value as? String, !text.isEmpty {
            return text
        }

        if let markerRange,
           let fallback = selectedTextFromMarkerRange(in: element, markerRange: markerRange),
           !fallback.isEmpty {
            return fallback
        }

        if let selectedRange,
           let fallback = selectedTextFromValue(in: element, selectedRange: selectedRange),
           !fallback.isEmpty {
            return fallback
        }

        switch error {
        case .success:
            throw SelectionCaptureError.noSelection
        case .attributeUnsupported, .notImplemented:
            throw SelectionCaptureError.unsupported
        default:
            throw map(error)
        }
    }

    private func selectedTextMarkerRange(in element: AXUIElement) -> CFTypeRef? {
        var markerRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            "AXSelectedTextMarkerRange" as CFString,
            &markerRange
        ) == .success,
        let markerRange,
        CFGetTypeID(markerRange) == AXTextMarkerRangeGetTypeID()
        else { return nil }
        return markerRange
    }

    private func selectedTextFromMarkerRange(
        in element: AXUIElement,
        markerRange: CFTypeRef
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXStringForTextMarkerRange" as CFString,
            markerRange,
            &value
        ) == .success,
        let text = value as? String
        else { return nil }
        return text
    }

    private func selectedTextRange(in element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range), range.length > 0 else { return nil }
        return range
    }

    private func selectedTextFromValue(
        in element: AXUIElement,
        selectedRange: CFRange
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        ) == .success,
        let text = value as? String
        else { return nil }

        let string = text as NSString
        let range = NSRange(location: selectedRange.location, length: selectedRange.length)
        guard range.location >= 0,
              range.length > 0,
              NSMaxRange(range) <= string.length else { return nil }
        return string.substring(with: range)
    }

    private func selectionBounds(for range: CFRange, in element: AXUIElement) -> CGRect? {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else { return nil }

        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgRect else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect), !rect.isEmpty else { return nil }
        return appKitRect(fromAccessibilityRect: rect)
    }

    private func selectionBounds(
        forTextMarkerRange markerRange: CFTypeRef,
        in element: AXUIElement
    ) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForTextMarkerRange" as CFString,
            markerRange,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgRect else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect), !rect.isEmpty else { return nil }
        return appKitRect(fromAccessibilityRect: rect)
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func role(of element: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &value
        ) == .success,
        let role = value as? String
        else { return "unknown" }
        return role
    }

    private func appKitRect(fromAccessibilityRect rect: CGRect) -> CGRect {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { continue }
            let quartzFrame = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            guard quartzFrame.contains(center) else { continue }
            return CGRect(
                x: screen.frame.minX + rect.minX - quartzFrame.minX,
                y: screen.frame.maxY - (rect.maxY - quartzFrame.minY),
                width: rect.width,
                height: rect.height
            )
        }

        guard let primaryScreen = NSScreen.screens.first else { return rect }
        return CGRect(
            x: rect.minX,
            y: primaryScreen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func accessibilityPoint(fromAppKitPoint point: CGPoint) -> CGPoint {
        for screen in NSScreen.screens where screen.frame.contains(point) {
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { continue }
            let quartzFrame = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            return CGPoint(
                x: quartzFrame.minX + point.x - screen.frame.minX,
                y: quartzFrame.minY + screen.frame.maxY - point.y
            )
        }

        guard let primaryScreen = NSScreen.screens.first else { return point }
        return CGPoint(x: point.x, y: primaryScreen.frame.maxY - point.y)
    }

    private func map(_ error: AXError) -> SelectionCaptureError {
        switch error {
        case .apiDisabled:
            .permissionRequired
        case .attributeUnsupported, .parameterizedAttributeUnsupported, .notImplemented:
            .unsupported
        case .invalidUIElement, .cannotComplete, .failure:
            .sourceUnavailable
        default:
            .noFocusedElement
        }
    }
}

private extension SelectionCaptureError {
    var allowsClipboardFallback: Bool {
        switch self {
        case .noFocusedElement, .noSelection, .unsupported, .sourceUnavailable:
            true
        case .permissionRequired, .secureInput:
            false
        }
    }
}

private extension ClipboardSelectionFallbackError {
    var selectionCaptureError: SelectionCaptureError {
        switch self {
        case .sourceUnavailable, .clipboardChanged, .restoreFailed:
            .sourceUnavailable
        case .copyUnavailable, .timedOut, .unsafePasteboard:
            .unsupported
        }
    }
}
