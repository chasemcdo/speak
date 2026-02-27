import AppKit
import SwiftUI

/// Manages the lifecycle of the floating overlay panel.
@MainActor
@Observable
final class OverlayManager {
    private var panel: OverlayPanel?

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func show(appState: AppState) {
        if panel != nil {
            panel?.orderFront(nil)
            return
        }

        let overlayView = OverlayView()
            .environment(appState)

        let panel = OverlayPanel(contentView: overlayView, appState: appState)
        panel.orderFront(nil)
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}
