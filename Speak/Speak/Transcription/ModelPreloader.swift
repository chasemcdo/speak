import Foundation

/// Manages pre-downloading speech models so they're ready when recording starts.
@MainActor
final class ModelPreloader {
    private var tasksByLocale: [String: Task<Void, Never>] = [:]
    private let modelManager = ModelManager()

    /// Pre-download the speech model for the user's selected locale.
    func preload() {
        let locale = UserDefaults.standard.string(forKey: "locale")
            .flatMap { Locale(identifier: $0) } ?? Locale.current
        let localeID = locale.identifier(.bcp47)

        // Reuse an existing task if one is already preloading this locale
        if let existing = tasksByLocale[localeID], !existing.isCancelled {
            return
        }

        // Cancel any in-flight preloads for other locales
        for (_, task) in tasksByLocale {
            task.cancel()
        }
        tasksByLocale.removeAll()

        let task = Task { [weak self, modelManager] in
            do {
                try await modelManager.ensureModelAvailable(for: locale)
            } catch is CancellationError {
                return
            } catch {}

            guard let self else { return }
            if self.tasksByLocale[localeID] != nil {
                self.tasksByLocale.removeValue(forKey: localeID)
            }
        }
        tasksByLocale[localeID] = task
    }

    /// Wait for the preload matching the given locale, with a timeout.
    /// Returns after the preload completes or the timeout expires.
    func waitForPreload(localeID: String) async {
        guard let matchingTask = tasksByLocale[localeID] else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await withTaskCancellationHandler {
                    await matchingTask.value
                } onCancel: {
                    matchingTask.cancel()
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: Constants.modelPreloadTimeout)
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    /// Cancel all in-flight preloads.
    func cancelAll() {
        for (_, task) in tasksByLocale {
            task.cancel()
        }
        tasksByLocale.removeAll()
    }
}
