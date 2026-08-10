import AppKit
import Combine
import SwiftUI

@MainActor
final class SelectionOverlayCoordinator {
    private let store: SelectionOverlayStore
    private let panel: SelectionOverlayPanel
    private lazy var hostingController = NSHostingController(
        rootView: SelectionOverlayView(
            store: store,
            onToggleMore: { [weak self] in self?.toggleMore() }
        )
    )

    private var cancellables: Set<AnyCancellable> = []
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var synchronizationTask: Task<Void, Never>?
    private var positionedContextID: UUID?
    private var anchoredTopLeft: CGPoint?

    init(store: SelectionOverlayStore) {
        self.store = store
        panel = SelectionOverlayPanel(
            contentRect: CGRect(
                x: 0,
                y: 0,
                width: SelectionOverlayView.expandedWidth,
                height: OverlayPlacement.minimumPanelHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hostingController.sizingOptions = []
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
        panel.becomesKeyOnlyIfNeeded = true

        store.objectWillChange
            .sink { [weak self] _ in
                self?.schedulePanelSynchronization()
            }
            .store(in: &cancellables)

        installDismissMonitors()
        installWorkspaceMonitor()
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
        anchoredTopLeft = nil
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

        let availableWidth = max(280, screen.visibleFrame.width - OverlayPlacement.edgeInset * 2)
        let availableHeight = max(80, screen.visibleFrame.height - OverlayPlacement.edgeInset * 2)
        let maximumSize = CGSize(
            width: min(SelectionOverlayView.expandedWidth, availableWidth),
            height: min(360, availableHeight)
        )
        let fittingSize = hostingController.sizeThatFits(in: maximumSize)
        let size = CGSize(
            width: maximumSize.width,
            height: min(
                max(OverlayPlacement.minimumPanelHeight, ceil(fittingSize.height)),
                maximumSize.height
            )
        )
        let wasVisible = panel.isVisible
        let keepsCurrentAnchor = wasVisible
            && positionedContextID == context.id
            && anchoredTopLeft != nil
        let frame: CGRect
        if keepsCurrentAnchor, let anchoredTopLeft {
            frame = OverlayPlacement.resizedFrame(
                anchoredTopLeft: anchoredTopLeft,
                panelSize: size,
                visibleFrame: screen.visibleFrame
            )
        } else {
            frame = OverlayPlacement.calculate(
                anchor: anchor,
                panelSize: size,
                visibleFrame: screen.visibleFrame
            )
            positionedContextID = context.id
        }
        if store.isMorePresented {
            panel.allowsKeyboardInput = true
        } else {
            if panel.isKeyWindow {
                panel.resignKey()
            }
            panel.allowsKeyboardInput = false
        }
        panel.setFrame(frame, display: true, animate: false)
        if !keepsCurrentAnchor {
            anchoredTopLeft = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
        }
        if !wasVisible {
            panel.orderFrontRegardless()
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

    private func toggleMore() {
        guard store.isVisible else { return }

        if store.isMorePresented {
            store.hideMore()
        } else {
            store.showMore()
        }

        synchronizationTask?.cancel()
        synchronizationTask = nil
        synchronizePanel()
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    private func installDismissMonitors() {
        // Keep ordinary key events completely outside ClipAll. Observing `.keyDown`
        // here disrupts source-app input method composition and can duplicate text.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                guard let self, self.store.isVisible, !self.panel.frame.contains(location) else { return }
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

}

private final class SelectionOverlayPanel: NSPanel {
    var allowsKeyboardInput = false

    override var canBecomeKey: Bool { allowsKeyboardInput }
    override var canBecomeMain: Bool { false }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
