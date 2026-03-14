import AppKit

/// Handles delivering transcribed text via paste or clipboard, including paste-failed hints.
@MainActor
final class TextDeliveryService {
    private let pasteService: any Pasting
    private let overlayManager: any OverlayPresenting
    private let appState: AppState

    private var pasteFailedHintTask: Task<Void, Never>?

    /// Called after a successful paste when auto-learn is appropriate.
    var onPasteSucceeded: ((_ text: String, _ app: NSRunningApplication?) -> Void)?

    init(pasteService: any Pasting, overlayManager: any OverlayPresenting, appState: AppState) {
        self.pasteService = pasteService
        self.overlayManager = overlayManager
        self.appState = appState
    }

    /// Deliver text via auto-paste or clipboard copy.
    func deliver(_ text: String, autoPaste: Bool, into app: NSRunningApplication?) async {
        overlayManager.hide()

        if autoPaste {
            let success = await pasteService.paste(text, into: app)
            if success {
                onPasteSucceeded?(text, app)
            } else {
                showPasteFailedHint(text: text)
            }
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            app?.activate()
        }
    }

    /// Show the paste-failed hint overlay and schedule auto-dismiss.
    func showPasteFailedHint(text: String) {
        pasteFailedHintTask?.cancel()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        SoundFeedback.playPasteFailedSound()
        appState.pasteFailedHint = true
        overlayManager.show(appState: appState)

        pasteFailedHintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Constants.pasteFailedHintDuration))
            guard !Task.isCancelled else { return }
            self?.dismissPasteFailedHint()
        }
    }

    /// Dismiss the paste-failed hint if it's still showing.
    func dismissPasteFailedHint() {
        guard appState.pasteFailedHint else { return }
        pasteFailedHintTask?.cancel()
        pasteFailedHintTask = nil
        overlayManager.hide()
        appState.pasteFailedHint = false
    }
}
