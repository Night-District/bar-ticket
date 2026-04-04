import AppKit
import SwiftUI

/// Controller that manages the floating Dynamic Island window
@MainActor
final class DynamicIslandController {

    private var window: NSWindow?
    private var hostingView: NSHostingView<DynamicIslandView>?
    private var islandViewModel = DynamicIslandViewModel()
    private var dismissTask: Task<Void, Never>?

    init() {
        setupWindow()
    }

    private func setupWindow() {
        let view = DynamicIslandView(viewModel: islandViewModel)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 340, height: 48)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 48),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.contentView = hosting
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        // Position at top-center of main screen, near the notch
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let visibleFrame = screen.visibleFrame
            let notchHeight = screenFrame.height - visibleFrame.height - (visibleFrame.origin.y - screenFrame.origin.y)
            let windowX = screenFrame.midX - 170
            let windowY = screenFrame.maxY - notchHeight - 56
            window.setFrameOrigin(NSPoint(x: windowX, y: windowY))
        }

        self.window = window
        self.hostingView = hosting
    }

    func show(state: IslandState) {
        dismissTask?.cancel()

        islandViewModel.update(state: state)
        window?.orderFrontRegardless()
        window?.alphaValue = 1.0

        // Auto-dismiss based on state
        switch state {
        case .confirmed:
            scheduleDismiss(after: Constants.islandConfirmDuration)
        case .error:
            scheduleDismiss(after: Constants.islandErrorDuration)
        default:
            break
        }
    }

    func dismiss() {
        dismissTask?.cancel()

        // Fade out animation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
            self?.islandViewModel.update(state: .hidden)
        })
    }

    private func scheduleDismiss(after delay: TimeInterval) {
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    /// Make the confirmed state clickable to open the issue URL
    func setClickHandler(_ handler: @escaping (String) -> Void) {
        islandViewModel.onClickURL = handler
    }
}
