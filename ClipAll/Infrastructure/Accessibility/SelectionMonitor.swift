import AppKit
import Carbon.HIToolbox
import Foundation
import OSLog

private let clipAllHotKeySignature: OSType = 0x434C_5041 // "CLPA"
private let clipAllHotKeyIdentifier: UInt32 = 1

func matchesClipAllHotKeyEvent(
    _ event: EventRef?,
    signature: OSType,
    identifier: UInt32
) -> Bool {
    guard let event else { return false }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    return status == noErr
        && hotKeyID.signature == signature
        && hotKeyID.id == identifier
}

private let clipAllHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard matchesClipAllHotKeyEvent(
        event,
        signature: clipAllHotKeySignature,
        identifier: clipAllHotKeyIdentifier
    ), let userData else { return OSStatus(eventNotHandledErr) }
    let monitor = Unmanaged<SelectionMonitor>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        monitor.handleRegisteredHotKey()
    }
    return noErr
}

@MainActor
final class SelectionMonitor {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.wxy.ClipAll",
        category: "SelectionMonitor"
    )

    typealias SelectionHandler = @MainActor (SelectionContext) -> Void
    typealias PermissionHandler = @MainActor () -> Void
    typealias InvalidationHandler = @MainActor () -> Void
    typealias AutomaticDisplayPolicy = @MainActor (PointerSelectionIntent, String?) -> Bool
    typealias FrontmostBundleIdentifierProvider = @MainActor () -> String?

    private struct SelectionSignature: Equatable {
        let text: String
        let sourceBundleIdentifier: String?
        let bounds: CGRect?
    }

    private enum CaptureTrigger {
        case pointer(
            PointerSelectionIntent,
            sourceBundleIdentifier: String?,
            triggerLocation: CGPoint,
            fallbackPolicy: SelectionFallbackPolicy
        )
        case hotKey
        case manual

        var name: String {
            switch self {
            case let .pointer(intent, _, _, _):
                "pointer-\(intent.rawValue)"
            case .hotKey:
                "hotKey"
            case .manual:
                "manual"
            }
        }

        var fallbackPolicy: SelectionFallbackPolicy {
            switch self {
            case let .pointer(_, _, _, fallbackPolicy):
                fallbackPolicy
            case .hotKey, .manual:
                .enabled
            }
        }

        var triggerLocation: CGPoint {
            switch self {
            case let .pointer(_, _, triggerLocation, _):
                triggerLocation
            case .hotKey, .manual:
                NSEvent.mouseLocation
            }
        }
    }

    private let captureService: any SelectionCapturing
    private let allowsAutomaticDisplay: AutomaticDisplayPolicy
    private let frontmostBundleIdentifier: FrontmostBundleIdentifierProvider
    private let onSelection: SelectionHandler
    private let onPermissionRequired: PermissionHandler
    private let onSelectionInvalidated: InvalidationHandler

    private var shortcut: GlobalShortcutConfiguration
    private var mouseMonitor: Any?
    private var pointerGesture = PointerSelectionGesture()
    private var multiClickFallbackPolicy: SelectionFallbackPolicy?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var captureTask: Task<Void, Never>?
    private var lastSignature: SelectionSignature?
    private var lastCaptureDate = Date.distantPast

    private(set) var isRunning = false

    init(
        captureService: any SelectionCapturing,
        shortcut: GlobalShortcutConfiguration,
        allowsAutomaticDisplay: @escaping AutomaticDisplayPolicy = { _, _ in true },
        frontmostBundleIdentifier: @escaping FrontmostBundleIdentifierProvider = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        },
        onSelection: @escaping SelectionHandler,
        onPermissionRequired: @escaping PermissionHandler = {},
        onSelectionInvalidated: @escaping InvalidationHandler = {}
    ) {
        self.captureService = captureService
        self.shortcut = shortcut
        self.allowsAutomaticDisplay = allowsAutomaticDisplay
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
        self.onSelection = onSelection
        self.onPermissionRequired = onPermissionRequired
        self.onSelectionInvalidated = onSelectionInvalidated
    }

    func start() {
        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            ) { [weak self] event in
                let location = NSEvent.mouseLocation
                let clickCount = event.clickCount
                let isShiftPressed = event.modifierFlags.contains(.shift)
                switch event.type {
                case .leftMouseDown:
                    Task { @MainActor [weak self] in
                        self?.handlePointerDown(at: location, clickCount: clickCount)
                    }
                case .leftMouseDragged:
                    Task { @MainActor [weak self] in
                        self?.pointerGesture.update(at: location)
                    }
                case .leftMouseUp:
                    Task { @MainActor [weak self] in
                        self?.handlePointerUp(
                            at: location,
                            clickCount: clickCount,
                            isShiftPressed: isShiftPressed
                        )
                    }
                default:
                    break
                }
            }
        }

        let handlerStatus = installHotKeyHandlerIfNeeded()
        let hotKeyStatus = handlerStatus == noErr ? registerHotKey() : handlerStatus
        isRunning = mouseMonitor != nil || hotKeyRef != nil
        Self.logger.notice(
            "Selection monitor registration: running=\(self.isRunning, privacy: .public), pointer=\(self.mouseMonitor != nil, privacy: .public), hotKey=\(self.hotKeyRef != nil, privacy: .public), handlerStatus=\(handlerStatus, privacy: .public), hotKeyStatus=\(hotKeyStatus, privacy: .public)"
        )
    }

    func stop() {
        isRunning = false
        captureTask?.cancel()
        captureTask = nil
        lastSignature = nil
        pointerGesture.reset()
        multiClickFallbackPolicy = nil

        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        unregisterHotKey()
        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
            self.hotKeyHandlerRef = nil
        }
        Self.logger.notice("Selection monitor stopped")
    }

    func updateShortcut(_ shortcut: GlobalShortcutConfiguration) {
        self.shortcut = shortcut
        guard isRunning else { return }
        unregisterHotKey()
        _ = registerHotKey()
    }

    func captureNow() {
        scheduleCapture(
            after: .zero,
            allowsDuplicate: true,
            trigger: .manual,
            requiresRunning: false
        )
    }

    func handleRegisteredHotKey(requiresRunning: Bool = true) {
        guard isRunning || !requiresRunning else { return }
        scheduleCapture(
            after: .milliseconds(20),
            allowsDuplicate: true,
            trigger: .hotKey,
            requiresRunning: requiresRunning
        )
    }

    func handlePointerDown(at location: CGPoint, clickCount: Int) {
        pointerGesture.begin(at: location)
        multiClickFallbackPolicy = clickCount >= 2
            ? captureService.preflightFallbackPolicy(for: .multiClick, at: location)
            : nil
    }

    func handlePointerUp(
        at location: CGPoint,
        clickCount: Int,
        isShiftPressed: Bool,
        requiresRunning: Bool = true
    ) {
        let preflightPolicy = multiClickFallbackPolicy
        multiClickFallbackPolicy = nil
        guard isRunning || !requiresRunning,
              let intent = pointerGesture.end(
                  at: location,
                  clickCount: clickCount,
                  isShiftPressed: isShiftPressed
              ) else { return }
        capturePointerSelection(
            intent,
            sourceBundleIdentifier: frontmostBundleIdentifier(),
            triggerLocation: location,
            fallbackPolicy: intent == .multiClick
                ? preflightPolicy ?? .textHitRequired
                : intent.fallbackPolicy,
            requiresRunning: requiresRunning
        )
    }

    func capturePointerSelection(
        _ intent: PointerSelectionIntent,
        sourceBundleIdentifier: String?,
        triggerLocation: CGPoint = NSEvent.mouseLocation,
        fallbackPolicy: SelectionFallbackPolicy? = nil,
        after delay: Duration = .milliseconds(45),
        requiresRunning: Bool = true
    ) {
        guard isRunning || !requiresRunning else { return }
        captureTask?.cancel()
        captureTask = nil
        let trigger = CaptureTrigger.pointer(
            intent,
            sourceBundleIdentifier: sourceBundleIdentifier,
            triggerLocation: triggerLocation,
            fallbackPolicy: fallbackPolicy ?? intent.fallbackPolicy
        )
        guard validatePointerTrigger(trigger) else { return }
        scheduleCapture(
            after: delay,
            allowsDuplicate: false,
            trigger: trigger,
            requiresRunning: requiresRunning
        )
    }

    private func installHotKeyHandlerIfNeeded() -> OSStatus {
        guard hotKeyHandlerRef == nil else { return noErr }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        return InstallEventHandler(
            GetApplicationEventTarget(),
            clipAllHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandlerRef
        )
    }

    private func registerHotKey() -> OSStatus {
        guard hotKeyRef == nil else { return noErr }
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(
            signature: clipAllHotKeySignature,
            id: clipAllHotKeyIdentifier
        )
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            carbonModifiers(from: shortcut.modifierFlagsRawValue),
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr {
            hotKeyRef = reference
        }
        return status
    }

    private func unregisterHotKey() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    private func carbonModifiers(from rawValue: UInt) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: rawValue)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    private func scheduleCapture(
        after delay: Duration,
        allowsDuplicate: Bool,
        trigger: CaptureTrigger,
        requiresRunning: Bool = true
    ) {
        guard isRunning || !requiresRunning else { return }
        captureTask?.cancel()
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if delay != .zero {
                    try await Task.sleep(for: delay)
                }
                try Task.checkCancellation()
                guard validatePointerTrigger(trigger) else { return }
                Self.logger.info(
                    "Selection capture requested: trigger=\(trigger.name, privacy: .public), fallbackPolicy=\(trigger.fallbackPolicy.rawValue, privacy: .public)"
                )
                let context = try await captureService.captureCurrentSelection(
                    triggerLocation: trigger.triggerLocation,
                    fallbackPolicy: trigger.fallbackPolicy
                )
                guard !Task.isCancelled, self.isRunning || !requiresRunning else { return }
                guard validatePointerTrigger(trigger, context: context) else { return }
                guard allowsDuplicate || shouldPublish(context) else { return }
                onSelection(context)
            } catch let error as SelectionCaptureError {
                Self.logger.debug(
                    "Selection capture ended: trigger=\(trigger.name, privacy: .public), error=\(String(describing: error), privacy: .public)"
                )
                if error == .permissionRequired {
                    onPermissionRequired()
                } else {
                    onSelectionInvalidated()
                }
            } catch {
                Self.logger.error(
                    "Selection capture failed: trigger=\(trigger.name, privacy: .public), errorType=\(String(describing: type(of: error)), privacy: .public)"
                )
                onSelectionInvalidated()
            }
        }
    }

    private func validatePointerTrigger(
        _ trigger: CaptureTrigger,
        context: SelectionContext? = nil
    ) -> Bool {
        guard case let .pointer(intent, expectedBundleIdentifier, _, _) = trigger else {
            return true
        }
        let currentBundleIdentifier = frontmostBundleIdentifier()
        guard currentBundleIdentifier == expectedBundleIdentifier,
              context == nil
                || context?.sourceBundleIdentifier == expectedBundleIdentifier else {
            onSelectionInvalidated()
            Self.logger.info(
                "Selection capture suppressed: trigger=pointer-\(intent.rawValue, privacy: .public), bundleIdentifier=\(expectedBundleIdentifier ?? "unknown", privacy: .public), reason=sourceChanged"
            )
            return false
        }
        guard allowsAutomaticDisplay(intent, currentBundleIdentifier) else {
            onSelectionInvalidated()
            Self.logger.info(
                "Selection capture suppressed: trigger=pointer-\(intent.rawValue, privacy: .public), bundleIdentifier=\(currentBundleIdentifier ?? "unknown", privacy: .public), reason=userPolicy"
            )
            return false
        }
        if intent == .multiClick,
           let context,
           let selectionBounds = context.selectionBounds,
           !selectionBounds.insetBy(
               dx: -PointerSelectionGesture.minimumDragDistance,
               dy: -PointerSelectionGesture.minimumDragDistance
           ).contains(context.triggerLocation) {
            onSelectionInvalidated()
            Self.logger.info(
                "Selection capture suppressed: trigger=pointer-multiClick, bundleIdentifier=\(currentBundleIdentifier ?? "unknown", privacy: .public), reason=selectionOutsideTrigger"
            )
            return false
        }
        return true
    }

    private func shouldPublish(_ context: SelectionContext) -> Bool {
        let signature = SelectionSignature(
            text: context.normalizedText,
            sourceBundleIdentifier: context.sourceBundleIdentifier,
            bounds: context.selectionBounds
        )
        defer {
            lastSignature = signature
            lastCaptureDate = Date()
        }
        guard signature == lastSignature else { return true }
        return Date().timeIntervalSince(lastCaptureDate) > 1.2
    }
}
