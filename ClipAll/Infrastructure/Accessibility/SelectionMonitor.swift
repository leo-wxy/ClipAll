import AppKit
import Carbon.HIToolbox
import Foundation
import OSLog

private let clipAllHotKeySignature: OSType = 0x434C_5041 // "CLPA"
private let clipAllHotKeyIdentifier: UInt32 = 1

private let clipAllHotKeyHandler: EventHandlerUPP = { _, _, userData in
    guard let userData else { return OSStatus(eventNotHandledErr) }
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

    private struct SelectionSignature: Equatable {
        let text: String
        let sourceBundleIdentifier: String?
        let bounds: CGRect?
    }

    private enum CaptureTrigger: String {
        case pointer
        case hotKey
        case manual
    }

    private let captureService: any SelectionCapturing
    private let onSelection: SelectionHandler
    private let onPermissionRequired: PermissionHandler
    private let onSelectionInvalidated: InvalidationHandler

    private var shortcut: GlobalShortcutConfiguration
    private var mouseMonitor: Any?
    private var pointerGesture = PointerSelectionGesture()
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var captureTask: Task<Void, Never>?
    private var lastSignature: SelectionSignature?
    private var lastCaptureDate = Date.distantPast

    private(set) var isRunning = false

    init(
        captureService: any SelectionCapturing,
        shortcut: GlobalShortcutConfiguration,
        onSelection: @escaping SelectionHandler,
        onPermissionRequired: @escaping PermissionHandler = {},
        onSelectionInvalidated: @escaping InvalidationHandler = {}
    ) {
        self.captureService = captureService
        self.shortcut = shortcut
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
                        self?.pointerGesture.begin(at: location)
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

    fileprivate func handleRegisteredHotKey() {
        guard isRunning else { return }
        scheduleCapture(
            after: .milliseconds(20),
            allowsDuplicate: true,
            trigger: .hotKey
        )
    }

    private func handlePointerUp(
        at location: CGPoint,
        clickCount: Int,
        isShiftPressed: Bool
    ) {
        guard isRunning,
              pointerGesture.end(
                  at: location,
                  clickCount: clickCount,
                  isShiftPressed: isShiftPressed
              ) else { return }
        scheduleCapture(
            after: .milliseconds(45),
            allowsDuplicate: false,
            trigger: .pointer
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
                let context = try await captureService.captureCurrentSelection(
                    triggerLocation: NSEvent.mouseLocation
                )
                guard !Task.isCancelled, self.isRunning || !requiresRunning else { return }
                guard allowsDuplicate || shouldPublish(context) else { return }
                Self.logger.debug(
                    "Selection captured: trigger=\(trigger.rawValue, privacy: .public), hasBounds=\(context.selectionBounds != nil, privacy: .public)"
                )
                onSelection(context)
            } catch let error as SelectionCaptureError {
                Self.logger.debug(
                    "Selection capture ended: trigger=\(trigger.rawValue, privacy: .public), error=\(String(describing: error), privacy: .public)"
                )
                if error == .permissionRequired {
                    onPermissionRequired()
                } else {
                    onSelectionInvalidated()
                }
            } catch {
                Self.logger.error(
                    "Selection capture failed: trigger=\(trigger.rawValue, privacy: .public), errorType=\(String(describing: type(of: error)), privacy: .public)"
                )
                onSelectionInvalidated()
            }
        }
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
