import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
final class AccessibilityPermissionService: ObservableObject {
    @Published private(set) var isTrusted: Bool
    @Published private(set) var isAwaitingAuthorization = false

    private var monitoringTask: Task<Void, Never>?

    init() {
        isTrusted = AXIsProcessTrusted()
    }

    func refresh() {
        isTrusted = AXIsProcessTrusted()
        if isTrusted {
            isAwaitingAuthorization = false
            monitoringTask?.cancel()
            monitoringTask = nil
        }
    }

    func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true]
        isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if !isTrusted {
            isAwaitingAuthorization = true
            monitorAuthorization()
        }
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        isAwaitingAuthorization = true
        monitorAuthorization()
        NSWorkspace.shared.open(url)
    }

    private func monitorAuthorization() {
        monitoringTask?.cancel()
        monitoringTask = Task { [weak self] in
            for _ in 0..<120 {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let self else { return }
                self.refresh()
                if self.isTrusted { return }
            }
            self?.isAwaitingAuthorization = false
            self?.monitoringTask = nil
        }
    }
}
