import AppKit
import ApplicationServices

@MainActor
final class ForegroundAppWatcher {
    var onDirectoryChange: ((URL?) -> Void)?
    private var observer: NSObjectProtocol?

    func start() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor [weak self] in
                guard let self else { return }
                let dir = self.resolveDocumentDirectory(for: app)
                self.onDirectoryChange?(dir)
            }
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    private func resolveDocumentDirectory(for app: NSRunningApplication?) -> URL? {
        guard let app, AXIsProcessTrusted() else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef else { return nil }
        let win = windowRef as! AXUIElement
        var docRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXDocumentAttribute as CFString, &docRef) == .success,
              let docStr = docRef as? String else { return nil }
        return URL(string: docStr)?.standardizedFileURL.deletingLastPathComponent()
    }
}
