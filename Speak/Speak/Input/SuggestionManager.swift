import AppKit

/// Manages dictionary suggestion detection, display, and acceptance.
@MainActor
final class SuggestionManager {
    private let dictionaryStore: DictionaryStore?
    private let overlayManager: any OverlayPresenting
    private let appState: AppState

    private var editDetectionTask: Task<Void, Never>?
    private var suggestionDismissTask: Task<Void, Never>?

    /// Called when the user accepts a suggestion and filters should be reconfigured.
    var onAccepted: (() -> Void)?

    init(dictionaryStore: DictionaryStore?, overlayManager: any OverlayPresenting, appState: AppState) {
        self.dictionaryStore = dictionaryStore
        self.overlayManager = overlayManager
        self.appState = appState
    }

    /// Schedule a delayed read of the target app's text field to detect user corrections.
    func scheduleEditDetection(pastedText: String, into app: NSRunningApplication?) {
        let store = dictionaryStore
        editDetectionTask?.cancel()
        editDetectionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Constants.editDetectionDelay))
            guard !Task.isCancelled else { return }
            let currentText = await Task.detached {
                ContextReader.readContextFromApp(app)
            }.value
            guard let currentText, !Task.isCancelled else { return }
            let candidates = EditDiffer.findReplacements(original: pastedText, edited: currentText)
            guard !Task.isCancelled else { return }
            if let candidate = candidates.first {
                let suggestion = DictionarySuggestion(
                    phrase: candidate.replacement,
                    original: candidate.original
                )
                store?.addSuggestion(suggestion)
                self?.show(suggestion)
            }
        }
    }

    /// Cancel any pending edit detection.
    func cancelEditDetection() {
        editDetectionTask?.cancel()
        editDetectionTask = nil
    }

    /// Show a suggestion in the overlay. Auto-dismisses after timeout.
    func show(_ suggestion: DictionarySuggestion) {
        suggestionDismissTask?.cancel()
        appState.suggestedWord = suggestion
        overlayManager.show(appState: appState)

        suggestionDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Constants.suggestionAutoDismiss))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// Dismiss the suggestion overlay without accepting.
    func dismiss() {
        guard appState.suggestedWord != nil else { return }
        suggestionDismissTask?.cancel()
        suggestionDismissTask = nil
        overlayManager.hide()
        appState.suggestedWord = nil
    }

    /// Accept the current suggestion, add to dictionary, and dismiss.
    func accept() {
        guard let suggestion = appState.suggestedWord else { return }
        dictionaryStore?.acceptSuggestion(suggestion)
        onAccepted?()
        dismiss()
    }
}
