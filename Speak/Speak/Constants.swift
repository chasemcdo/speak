import Foundation

enum Constants {
    /// Delay before reading the target app's text field to detect user corrections.
    static let editDetectionDelay: TimeInterval = 3

    /// How long the preview overlay stays visible before auto-dismissing.
    static let previewAutoDismiss: TimeInterval = 8

    /// How long the suggestion overlay stays visible before auto-dismissing.
    static let suggestionAutoDismiss: TimeInterval = 6

    /// How long the paste-failed hint stays visible before auto-dismissing.
    static let pasteFailedHintDuration: TimeInterval = 2

    /// Minimum string similarity score for dictionary replacement and edit detection.
    static let similarityThreshold: Double = 0.5

    /// Maximum nanoseconds to wait for a preloading speech model before proceeding.
    static let modelPreloadTimeout: UInt64 = 10_000_000_000
}
