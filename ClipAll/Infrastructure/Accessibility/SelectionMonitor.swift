import AppKit
import Carbon.HIToolbox
import Foundation

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
    typealias SelectionHandler = @MainActor (SelectionContext) -> Void
    typealias PermissionHandler = @MainActor () -> Void
    typealias InvalidationHandler = @MainActor () -> Void

    private struct SelectionSignature: Equatable {
        let text: String
        let sourceBundleIdentifier: String?
        let bounds: CGRect?
    }

    private let captureService: any SelectionCapturing
    private let onSelection: SelectionHandler
    private let onPermissionRequired: PermissionHandler
    private let onSelectionInvalidated: InvalidationHandler

    private var shortcut: GlobalShortcutConfiguration
    private var mouseMonitor: Any?
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
        guard !isRunning else { return }
        isRunning = true

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleCapture(
                    after: .milliseconds(45),
                    allowsDuplicate: false
                )
            }
        }
        installHotKeyHandlerIfNeeded()
        registerHotKey()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        captureTask?.cancel()
        captureTask = nil
        lastSignature = nil

        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        unregisterHotKey()
        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
            self.hotKeyHandlerRef = nil
        }
    }

    func updateShortcut(_ shortcut: GlobalShortcutConfiguration) {
        self.shortcut = shortcut
        guard isRunning else { return }
        unregisterHotKey()
        registerHotKey()
    }

    func captureNow() {
        scheduleCapture(
            after: .zero,
            allowsDuplicate: true,
            requiresRunning: false
        )
    }

    fileprivate func handleRegisteredHotKey() {
        guard isRunning else { return }
        scheduleCapture(
            after: .milliseconds(20),
            allowsDuplicate: true
        )
    }

    private func installHotKeyHandlerIfNeeded() {
        guard hotKeyHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            clipAllHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandlerRef
        )
    }

    private func registerHotKey() {
        guard hotKeyRef == nil else { return }
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
                let context = try captureService.captureCurrentSelection(
                    triggerLocation: NSEvent.mouseLocation
                )
                guard !Task.isCancelled, self.isRunning || !requiresRunning else { return }
                guard allowsDuplicate || shouldPublish(context) else { return }
                onSelection(context)
            } catch let error as SelectionCaptureError {
                if error == .permissionRequired {
                    onPermissionRequired()
                } else {
                    onSelectionInvalidated()
                }
            } catch {
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
