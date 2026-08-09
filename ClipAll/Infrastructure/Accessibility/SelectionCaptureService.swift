import AppKit
import ApplicationServices
import Foundation

enum SelectionCaptureError: Error, LocalizedError, Equatable, Sendable {
    case permissionRequired
    case noFocusedElement
    case noSelection
    case unsupported
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
        case .sourceUnavailable:
            "来源应用暂时无法响应"
        }
    }
}

@MainActor
protocol SelectionCapturing: AnyObject {
    func captureCurrentSelection(
        triggerLocation: CGPoint,
        includesEditableContent: Bool
    ) throws -> SelectionContext
}

@MainActor
final class SelectionCaptureService: SelectionCapturing {
    private let systemWideElement: AXUIElement

    init(systemWideElement: AXUIElement = AXUIElementCreateSystemWide()) {
        self.systemWideElement = systemWideElement
    }

    func captureCurrentSelection(
        triggerLocation: CGPoint = NSEvent.mouseLocation,
        includesEditableContent: Bool = true
    ) throws -> SelectionContext {
        guard AXIsProcessTrusted() else {
            throw SelectionCaptureError.permissionRequired
        }

        let focusedElement = try focusedUIElement()
        if !includesEditableContent, isEditableTextElement(focusedElement) {
            throw SelectionCaptureError.unsupported
        }
        let selectedRange = selectedTextRange(in: focusedElement)
        let selectedText = try selectedText(in: focusedElement, selectedRange: selectedRange)
        let bounds = textMarkerSelectionBounds(in: focusedElement)
            ?? selectedRange.flatMap { selectionBounds(for: $0, in: focusedElement) }
        let source = NSWorkspace.shared.frontmostApplication

        if let sourceBundleIdentifier = source?.bundleIdentifier,
           let ownBundleIdentifier = Bundle.main.bundleIdentifier,
           sourceBundleIdentifier == ownBundleIdentifier {
            throw SelectionCaptureError.noSelection
        }

        guard let context = SelectionContext(
            text: selectedText,
            sourceBundleIdentifier: source?.bundleIdentifier,
            sourceApplicationName: source?.localizedName,
            selectionBounds: bounds,
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

    private func isEditableTextElement(_ element: AXUIElement) -> Bool {
        var isSettable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &isSettable
        ) == .success,
        isSettable.boolValue {
            return true
        }

        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleValue
        ) == .success,
        let role = roleValue as? String
        else { return false }

        let editableRoles = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            kAXDateFieldRole as String,
            kAXTimeFieldRole as String,
        ]
        if editableRoles.contains(role) {
            return true
        }

        var subroleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSubroleAttribute as CFString,
            &subroleValue
        ) == .success,
        let subrole = subroleValue as? String
        else { return false }

        return subrole == kAXSearchFieldSubrole as String
    }

    private func selectedText(
        in element: AXUIElement,
        selectedRange: CFRange?
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

    private func textMarkerSelectionBounds(in element: AXUIElement) -> CGRect? {
        var markerRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            "AXSelectedTextMarkerRange" as CFString,
            &markerRange
        ) == .success,
        let markerRange,
        CFGetTypeID(markerRange) == AXTextMarkerRangeGetTypeID()
        else { return nil }

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
