import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

enum ClipboardSelectionFallbackError: Error, Equatable, Sendable {
    case sourceUnavailable
    case copyUnavailable
    case timedOut
    case unsafePasteboard
    case nonTextContent
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

    private enum Snapshot {
        case native([NativeItem])
        case appKit([NSPasteboardItem])
    }

    private struct NativeItem {
        let flavors: [NativeFlavor]
    }

    private struct NativeFlavor {
        let type: String
        let data: Data
        let flags: PasteboardFlavorFlags
    }

    private static let maximumItems = 16
    private static let maximumTypes = 64
    private static let maximumBytes = 32 * 1_024 * 1_024
    private static let pasteboardTagClass = UTTagClass(rawValue: "com.apple.nspboard-type")
    private static let nonTextObjectTypeIdentifiers: Set<String> = [
        NSPasteboard.PasteboardType.fileURL.rawValue,
        "Apple URL pasteboard type",
        "NSFilenamesPboardType",
        "NSFilesPromisePboardType",
        "com.apple.finder.noderef",
        "com.apple.filepromise",
        "com.apple.pasteboard.promised-file-content-type",
        "com.apple.pasteboard.promised-file-url",
        "com.adobe.pdf",
        "com.apple.icns",
        "com.apple.quicktime-movie",
        "com.compuserve.gif",
        "com.microsoft.bmp",
        "com.microsoft.waveform-audio",
        "fndf",
        "org.gnu.gnu-zip-archive",
        "org.webmproject.webp",
        "public.aiff-audio",
        "public.archive",
        "public.audio",
        "public.audiovisual-content",
        "public.font",
        "public.heic",
        "public.image",
        "public.jpeg",
        "public.movie",
        "public.mp3",
        "public.mpeg-4",
        "public.mpeg-4-audio",
        "public.opentype-font",
        "public.png",
        "public.tar-archive",
        "public.tiff",
        "public.truetype-font",
        "public.vcard",
        "public.zip-archive",
        "text/uri-list",
        "x-special/gnome-copied-files",
    ]

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
                    } else if capturedChangeCount == nil {
                        capturedChangeCount = currentChangeCount
                    }

                    if containsNonTextObject() {
                        throw ClipboardSelectionFallbackError.nonTextContent
                    }

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

    private func containsNonTextObject() -> Bool {
        guard let items = pasteboard.pasteboardItems else { return false }
        return items.contains { item in
            item.types.contains { type in
                let identifier = type.rawValue
                if Self.isNonTextObjectType(identifier) {
                    return true
                }

                let pasteboardAliases = UTType(identifier)?.tags[Self.pasteboardTagClass] ?? []
                if pasteboardAliases.contains(where: Self.isNonTextObjectType) {
                    return true
                }
                return false
            }
        }
    }

    private static func isNonTextObjectType(_ identifier: String) -> Bool {
        if nonTextObjectTypeIdentifiers.contains(identifier) {
            return true
        }
        let normalized = identifier.lowercased()
        return normalized.contains("filepromise") || normalized.contains("promised-file")
    }

    private func snapshotPasteboard() throws -> Snapshot {
        if let nativePasteboard = pasteboard as? NSPasteboard {
            return .native(try snapshotNativePasteboard(nativePasteboard))
        }

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

        return .appKit(copiedItems)
    }

    private func snapshotNativePasteboard(_ source: NSPasteboard) throws -> [NativeItem] {
        guard let nativePasteboard = Self.nativePasteboard(named: source.name) else {
            throw ClipboardSelectionFallbackError.unsafePasteboard
        }
        _ = PasteboardSynchronize(nativePasteboard)

        var itemCount = 0
        guard PasteboardGetItemCount(nativePasteboard, &itemCount) == noErr,
              itemCount <= Self.maximumItems else {
            throw ClipboardSelectionFallbackError.unsafePasteboard
        }

        var totalTypes = 0
        var totalBytes = 0
        var items: [NativeItem] = []
        items.reserveCapacity(itemCount)

        for index in 0..<itemCount {
            var itemIdentifier: PasteboardItemID?
            guard PasteboardGetItemIdentifier(
                nativePasteboard,
                CFIndex(index + 1),
                &itemIdentifier
            ) == noErr,
                let itemIdentifier else {
                throw ClipboardSelectionFallbackError.unsafePasteboard
            }

            var flavorArray: CFArray?
            guard PasteboardCopyItemFlavors(
                nativePasteboard,
                itemIdentifier,
                &flavorArray
            ) == noErr,
                let flavorTypes = flavorArray as? [String] else {
                throw ClipboardSelectionFallbackError.unsafePasteboard
            }

            var flavors: [NativeFlavor] = []
            for flavorType in flavorTypes {
                var flags = PasteboardFlavorFlags()
                guard PasteboardGetItemFlavorFlags(
                    nativePasteboard,
                    itemIdentifier,
                    flavorType as CFString,
                    &flags
                ) == noErr else {
                    throw ClipboardSelectionFallbackError.unsafePasteboard
                }
                guard !flags.contains(.systemTranslated) else { continue }

                totalTypes += 1
                guard totalTypes <= Self.maximumTypes else {
                    throw ClipboardSelectionFallbackError.unsafePasteboard
                }

                var flavorData: CFData?
                guard PasteboardCopyItemFlavorData(
                    nativePasteboard,
                    itemIdentifier,
                    flavorType as CFString,
                    &flavorData
                ) == noErr,
                    let flavorData else {
                    throw ClipboardSelectionFallbackError.unsafePasteboard
                }
                let data = flavorData as Data
                totalBytes += data.count
                guard totalBytes <= Self.maximumBytes else {
                    throw ClipboardSelectionFallbackError.unsafePasteboard
                }

                flags.remove([.systemTranslated, .promised])
                flavors.append(NativeFlavor(type: flavorType, data: data, flags: flags))
            }

            guard !flavors.isEmpty else {
                throw ClipboardSelectionFallbackError.unsafePasteboard
            }
            items.append(NativeItem(flavors: flavors))
        }

        return items
    }

    private func restore(_ snapshot: Snapshot, expectedChangeCount: Int) throws {
        guard pasteboard.changeCount == expectedChangeCount else {
            throw ClipboardSelectionFallbackError.clipboardChanged
        }

        switch snapshot {
        case let .native(items):
            guard let destination = pasteboard as? NSPasteboard,
                  let nativePasteboard = Self.nativePasteboard(named: destination.name),
                  PasteboardClear(nativePasteboard) == noErr else {
                throw ClipboardSelectionFallbackError.restoreFailed
            }

            for (index, item) in items.enumerated() {
                guard let itemIdentifier = UnsafeMutableRawPointer(bitPattern: index + 1) else {
                    throw ClipboardSelectionFallbackError.restoreFailed
                }
                for flavor in item.flavors {
                    guard PasteboardPutItemFlavor(
                        nativePasteboard,
                        itemIdentifier,
                        flavor.type as CFString,
                        flavor.data as CFData,
                        flavor.flags
                    ) == noErr else {
                        throw ClipboardSelectionFallbackError.restoreFailed
                    }
                }
            }
        case let .appKit(items):
            pasteboard.clearContents()
            guard items.isEmpty
                    || pasteboard.writeObjects(items.map { $0 as NSPasteboardWriting }) else {
                throw ClipboardSelectionFallbackError.restoreFailed
            }
        }
    }

    private static func nativePasteboard(named name: NSPasteboard.Name) -> Pasteboard? {
        var pasteboard: Pasteboard?
        guard PasteboardCreate(name.rawValue as CFString, &pasteboard) == noErr else { return nil }
        return pasteboard
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
