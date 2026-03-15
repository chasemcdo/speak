import AppKit
import SwiftUI

final class OverlayPanel: NSPanel {
    weak var appState: AppState?
    var onAction: ((OverlayAction) -> Void)?

    init(contentView: some View, appState: AppState? = nil, onAction: ((OverlayAction) -> Void)? = nil) {
        self.appState = appState
        self.onAction = onAction
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow

        let hostingView = FirstMouseHostingView(rootView: contentView)
        self.contentView = hostingView

        positionAtBottomCenter()
    }

    /// Position the panel at the bottom center of the main screen, above the dock.
    func positionAtBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth = frame.width
        let x = screenFrame.midX - (panelWidth / 2)
        let y = screenFrame.minY + 80
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Allow Escape key to cancel
    override func cancelOperation(_ sender: Any?) {
        onAction?(.cancel)
    }

    /// Allow Return key to confirm or accept suggestion
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // Return
            if case .suggestion = appState?.overlayMode {
                onAction?(.acceptSuggestion)
            } else {
                onAction?(.confirm)
            }
        } else {
            super.keyDown(with: event)
        }
    }
}

/// NSHostingView subclass that accepts the first mouse click, allowing buttons
/// in the non-activating panel to respond without requiring a prior click to focus.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
