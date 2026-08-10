import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum ClipboardSelectionFallbackError: Error, Equatable, Sendable {
    case sourceUnavailable
    case copyUnavailable
    case timedOut
    case unsafePasteboard
    case clipboardChanged
    case restoreFailed
}

@MainActor
protocol ClipboardPasteboard: AnyObject {
    var changeCount: Int { get }
    var pasteboardItems: [NSPasteboardItem]? { get }

    @discardableResult
    func clearContents() -> Int
    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool
}

extension NSPasteboard: ClipboardPasteboard {}

@MainActor
final class ClipboardSelectionFallback {
    typealias CopyAction = @MainActor (pid_t) -> Bool
    typealias SourceCheck = @MainActor (pid_t) -> Bool

    private struct Snapshot {
        let items: [NSPasteboardItem]
    }

    private static let maximumItems = 16
    private static let maximumTypes = 64
    private static let maximumBytes = 32 * 1_024 * 1_024

    private let pasteboard: any ClipboardPasteboard
    private let timeout: Duration
    private let pollInterval: Duration
    private let stabilityDelay: Duration
    private let sendCopy: CopyAction
    private let isSourceFrontmost: SourceCheck

    init(
        pasteboard: any ClipboardPasteboard = NSPasteboard.general,
        timeout: Duration = .milliseconds(650),
        pollInterval: Duration = .milliseconds(10),
        stabilityDelay: Duration = .milliseconds(20),
        sendCopy: CopyAction? = nil,
        isSourceFrontmost: SourceCheck? = nil
    ) {
        self.pasteboard = pasteboard
        self.timeout = timeout
        self.pollInterval = pollInterval
        self.stabilityDelay = stabilityDelay
        self.sendCopy = sendCopy ?? Self.postCopyShortcut
        self.isSourceFrontmost = isSourceFrontmost ?? { processIdentifier in
            NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier
        }
    }

    func captureSelection(sourceProcessIdentifier: pid_t) async throws -> String {
        guard isSourceFrontmost(sourceProcessIdentifier) else {
            throw ClipboardSelectionFallbackError.sourceUnavailable
        }

        let snapshot = try snapshotPasteboard()
        pasteboard.clearContents()
        let clearedChangeCount = pasteboard.changeCount
        var capturedChangeCount: Int?
        var restoreAttempted = false

        do {
            guard sendCopy(sourceProcessIdentifier) else {
                throw ClipboardSelectionFallbackError.copyUnavailable
            }

            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: timeout)
            while clock.now < deadline {
                try Task.checkCancellation()
                guard isSourceFrontmost(sourceProcessIdentifier) else {
                    throw ClipboardSelectionFallbackError.sourceUnavailable
                }

                let currentChangeCount = pasteboard.changeCount
                if currentChangeCount != clearedChangeCount {
                    if let capturedChangeCount, currentChangeCount != capturedChangeCount {
                        throw ClipboardSelectionFallbackError.clipboardChanged
                    }
                    capturedChangeCount = currentChangeCount

                    if let text = pasteboard.string(forType: .string),
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        try await Task.sleep(for: stabilityDelay)
                        try Task.checkCancellation()
                        guard isSourceFrontmost(sourceProcessIdentifier) else {
                            throw ClipboardSelectionFallbackError.sourceUnavailable
                        }
                        guard pasteboard.changeCount == currentChangeCount else {
                            throw ClipboardSelectionFallbackError.clipboardChanged
                        }

                        restoreAttempted = true
                        try restore(snapshot, expectedChangeCount: currentChangeCount)
                        return text
                    }
                }

                try await Task.sleep(for: pollInterval)
            }

            throw ClipboardSelectionFallbackError.timedOut
        } catch {
            if !restoreAttempted,
               error as? ClipboardSelectionFallbackError != .clipboardChanged {
                restoreAttempted = true
                let expectedChangeCount = capturedChangeCount ?? clearedChangeCount
                do {
                    try restore(snapshot, expectedChangeCount: expectedChangeCount)
                } catch {
                    throw error
                }
            }
            throw error
        }
    }

    private func snapshotPasteboard() throws -> Snapshot {
        let sourceItems = pasteboard.pasteboardItems ?? []
        guard sourceItems.count <= Self.maximumItems else {
            throw ClipboardSelectionFallbackError.unsafePasteboard
        }

        var totalTypes = 0
        var totalBytes = 0
        var copiedItems: [NSPasteboardItem] = []
        copiedItems.reserveCapacity(sourceItems.count)

        for sourceItem in sourceItems {
            let types = sourceItem.types
            guard !types.isEmpty else {
                throw ClipboardSelectionFallbackError.unsafePasteboard
            }
            totalTypes += types.count
            guard totalTypes <= Self.maximumTypes else {
                throw ClipboardSelectionFallbackError.unsafePasteboard
            }

            let copiedItem = NSPasteboardItem()
            for type in types {
                guard let data = sourceItem.data(forType: type) else {
                    throw ClipboardSelectionFallbackError.unsafePasteboard
                }
                totalBytes += data.count
                guard totalBytes <= Self.maximumBytes else {
                    throw ClipboardSelectionFallbackError.unsafePasteboard
                }
                copiedItem.setData(data, forType: type)
            }
            copiedItems.append(copiedItem)
        }

        return Snapshot(items: copiedItems)
    }

    private func restore(_ snapshot: Snapshot, expectedChangeCount: Int) throws {
        guard pasteboard.changeCount == expectedChangeCount else {
            throw ClipboardSelectionFallbackError.clipboardChanged
        }

        pasteboard.clearContents()
        guard snapshot.items.isEmpty
                || pasteboard.writeObjects(snapshot.items.map { $0 as NSPasteboardWriting }) else {
            throw ClipboardSelectionFallbackError.restoreFailed
        }
    }

    private static func postCopyShortcut(to processIdentifier: pid_t) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(kVK_ANSI_C),
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(kVK_ANSI_C),
                  keyDown: false
              ) else { return false }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
        return true
    }
}
