import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class SelectionOverlayCoordinator {
    private let store: SelectionOverlayStore
    private let panel: SelectionOverlayPanel
    private let hostingController: NSHostingController<SelectionOverlayView>

    private var cancellables: Set<AnyCancellable> = []
    private var globalMouseMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localMouseMonitor: Any?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var panelResignKeyObserver: NSObjectProtocol?
    private var synchronizationTask: Task<Void, Never>?
    private var positionedContextID: UUID?
    private var lastPresentedFrame: CGRect?
    private var attachmentEdge: OverlayAttachmentEdge?

    init(store: SelectionOverlayStore) {
        self.store = store
        hostingController = NSHostingController(rootView: SelectionOverlayView(store: store))
        hostingController.sizingOptions = []
        panel = SelectionOverlayPanel(
            contentRect: CGRect(
                x: 0,
                y: 0,
                width: SelectionOverlayView.expandedWidth,
                height: 42
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.appearance = NSApp.effectiveAppearance
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController.view.layer?.isOpaque = false
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.isOpaque = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = false

        store.objectWillChange
            .sink { [weak self] _ in
                self?.schedulePanelSynchronization()
            }
            .store(in: &cancellables)

        installDismissMonitors()
        installWorkspaceMonitor()
        installPanelFocusMonitor()
    }

    func present(_ context: SelectionContext) {
        store.present(context)
        synchronizePanel()
    }

    func dismiss() {
        synchronizationTask?.cancel()
        synchronizationTask = nil
        store.dismiss()
        positionedContextID = nil
        lastPresentedFrame = nil
        attachmentEdge = nil
        if panel.isKeyWindow {
            panel.resignKey()
        }
        panel.allowsKeyboardInput = false
        panel.orderOut(nil)
    }

    private func synchronizePanel() {
        guard store.isVisible, let context = store.context else {
            panel.orderOut(nil)
            return
        }

        panel.appearance = NSApp.effectiveAppearance
        hostingController.view.invalidateIntrinsicContentSize()
        hostingController.view.layoutSubtreeIfNeeded()
        let anchor = context.selectionBounds ?? CGRect(
            origin: context.triggerLocation,
            size: CGSize(width: 1, height: 1)
        )
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor.center) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        let fittingSize = hostingController.view.fittingSize
        let availableWidth = max(280, screen.visibleFrame.width - OverlayPlacement.edgeInset * 2)
        let availableHeight = max(80, screen.visibleFrame.height - OverlayPlacement.edgeInset * 2)
        let size = CGSize(
            width: min(SelectionOverlayView.expandedWidth, availableWidth),
            height: min(max(40, fittingSize.height), min(360, availableHeight))
        )
        let wasVisible = panel.isVisible
        let keepsCurrentAnchor = wasVisible
            && positionedContextID == context.id
            && lastPresentedFrame != nil
        let frame: CGRect
        if keepsCurrentAnchor, let lastPresentedFrame, let attachmentEdge {
            frame = OverlayPlacement.resizedFrame(
                from: lastPresentedFrame,
                panelSize: size,
                visibleFrame: screen.visibleFrame,
                attachmentEdge: attachmentEdge
            )
        } else {
            frame = OverlayPlacement.calculate(
                anchor: anchor,
                panelSize: size,
                visibleFrame: screen.visibleFrame
            )
            positionedContextID = context.id
            attachmentEdge = OverlayPlacement.attachmentEdge(for: frame, anchor: anchor)
        }
        if store.isMorePresented {
            panel.allowsKeyboardInput = true
        } else {
            if panel.isKeyWindow {
                panel.resignKey()
            }
            panel.allowsKeyboardInput = false
        }
        if wasVisible {
            panel.setFrame(frame, display: true, animate: false)
        } else {
            let revealWidth = min(frame.width, max(54, frame.width * 0.42))
            let revealFrame = CGRect(
                x: frame.midX - revealWidth / 2,
                y: frame.minY,
                width: revealWidth,
                height: frame.height
            )
            panel.alphaValue = 0
            panel.setFrame(revealFrame, display: true, animate: false)
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { animation in
                animation.duration = 0.09
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
                panel.animator().alphaValue = 1
            }
        }
        lastPresentedFrame = frame
        if store.isMorePresented {
            panel.makeKey()
        }
    }

    private func schedulePanelSynchronization() {
        synchronizationTask?.cancel()
        synchronizationTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.synchronizePanel()
        }
    }

    private func installDismissMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                guard let self, self.store.isVisible, !self.panel.frame.contains(location) else { return }
                self.dismiss()
            }
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.store.isVisible, !self.panel.isKeyWindow else { return }
                self.dismiss()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, self.store.isVisible, event.window !== self.panel else { return }
                self.dismiss()
            }
            return event
        }

    }

    private func installWorkspaceMonitor() {
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            let bundleIdentifier = application?.bundleIdentifier
            Task { @MainActor [weak self] in
                guard let self,
                      self.store.isVisible,
                      bundleIdentifier != self.store.context?.sourceBundleIdentifier else { return }
                self.dismiss()
            }
        }
    }

    private func installPanelFocusMonitor() {
        panelResignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.store.isMorePresented else { return }
                self.dismiss()
            }
        }
    }
}

private final class SelectionOverlayPanel: NSPanel {
    var allowsKeyboardInput = false

    override var canBecomeKey: Bool { allowsKeyboardInput }
    override var canBecomeMain: Bool { false }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
