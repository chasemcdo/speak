import AppKit
import SwiftUI

/// Manages the lifecycle of the floating overlay panel.
@MainActor
@Observable
final class OverlayManager {
    private var panel: OverlayPanel?
    var onAction: ((OverlayAction) -> Void)?

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
            .environment(\.overlayAction, onAction)

        let panel = OverlayPanel(contentView: overlayView, appState: appState, onAction: onAction)
        panel.orderFront(nil)
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}
