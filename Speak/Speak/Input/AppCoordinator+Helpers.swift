import AppKit

// MARK: - Private Helpers

@MainActor
extension AppCoordinator {
    func handleStartError(_ error: Error, appState: AppState) {
        appState.error = error.localizedDescription
        appState.isRecording = false
        overlayManager.hide()
        audioLevelMonitor = nil
        appState.audioLevel = nil
        transcriptionEngine.levelMonitor = nil
    }

    func prewarmLLMIfEnabled() {
        if UserDefaults.standard.bool(forKey: "llmRewrite") {
            Task {
                await LLMRewriter.prewarm()
            }
        }
    }

    /// Stop transcription, run post-processing, and save to history.
    func stopAndProcess() async -> String {
        // Snapshot the paste target immediately so it can't change during async stop.
        previousApp = NSWorkspace.shared.frontmostApplication

        SoundFeedback.playStopSound()
        hotkeyManager.resetState()
        removeRecordingKeyMonitor()

        await transcriptionEngine.stopSession()
        appState?.isRecording = false
        audioLevelMonitor = nil
        appState?.audioLevel = nil
        transcriptionEngine.levelMonitor = nil

        // Read AX context after audio capture has stopped to avoid delaying it.
        capturedContext = contextReader.readContext(from: previousApp)
        if UserDefaults.standard.bool(forKey: "screenContext") {
            capturedVocabulary = contextReader.readScreenVocabulary(from: previousApp)
        }

        let rawText = appState?.displayText ?? ""
        var text = rawText

        if !text.isEmpty {
            configureFilters()

            if !textProcessor.filters.isEmpty {
                appState?.isPostProcessing = true

                let locale = UserDefaults.standard.string(forKey: "locale")
                    .flatMap { Locale(identifier: $0) } ?? Locale.current

                let context = ProcessingContext(
                    surroundingText: capturedContext,
                    screenVocabulary: capturedVocabulary,
                    locale: locale
                )

                text = await textProcessor.process(text, context: context)
                appState?.isPostProcessing = false
            }
        }

        if !text.isEmpty {
            historyStore?.add(HistoryEntry(
                rawText: rawText,
                processedText: text,
                sourceAppName: previousApp?.localizedName,
                sourceAppBundleID: previousApp?.bundleIdentifier
            ))
        }

        return text
    }

    /// Race the in-flight preload for `localeID` against a 10-second timeout.
    func awaitPreload(for localeID: String) async {
        guard let matchingTask = preloadTasksByLocale[localeID] else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await withTaskCancellationHandler {
                    await matchingTask.value
                } onCancel: {
                    matchingTask.cancel()
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 10 * 1_000_000_000) // 10s grace period
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    /// Install a global key monitor for Escape/Return during recording.
    /// The overlay panel is non-activating so it never receives keyboard events;
    /// this monitor catches them from the foreground app instead.
    func installRecordingKeyMonitor() {
        guard recordingKeyMonitor == nil else { return }

        recordingKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                guard let self, let appState = self.appState, appState.isRecording else { return }
                if event.keyCode == 53 { // Escape
                    await self.stopWithoutPaste()
                }
            }
        }
    }

    /// Remove the recording key monitor.
    func removeRecordingKeyMonitor() {
        if let recordingKeyMonitor {
            NSEvent.removeMonitor(recordingKeyMonitor)
        }
        recordingKeyMonitor = nil
    }

    /// Install a global key monitor for Escape/Return during preview.
    func installPreviewKeyMonitor() {
        guard previewKeyMonitor == nil else { return }

        previewKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                if event.keyCode == 53 { // Escape
                    self.dismissPreview()
                } else if event.keyCode == 36 { // Return
                    await self.pasteFromPreview()
                }
            }
        }
    }

    /// Remove preview-related monitors and timers.
    func removePreviewMonitors() {
        previewDismissTimer?.cancel()
        previewDismissTimer = nil
        if let previewKeyMonitor {
            NSEvent.removeMonitor(previewKeyMonitor)
        }
        previewKeyMonitor = nil
    }

    /// Deliver transcribed text via auto-paste or clipboard copy.
    func deliverText(_ text: String, autoPaste: Bool) async {
        overlayManager.hide()

        if autoPaste {
            let success = await pasteService.paste(text, into: previousApp)
            if !success {
                showPasteFailedHint(text: text)
            }
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            previousApp?.activate()
        }
    }

    /// Show the paste-failed hint overlay and schedule auto-dismiss.
    /// Copies `text` to the clipboard so the user can manually paste.
    func showPasteFailedHint(text: String) {
        guard let appState else { return }
        pasteFailedHintTimer?.cancel()
        pasteFailedHintTimer = nil
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        SoundFeedback.playPasteFailedSound()
        appState.pasteFailedHint = true
        overlayManager.show(appState: appState)

        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.dismissPasteFailedHint()
            }
        }
        pasteFailedHintTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    /// Dismiss the paste-failed hint if it's still showing.
    func dismissPasteFailedHint() {
        guard let appState, appState.pasteFailedHint else { return }
        pasteFailedHintTimer?.cancel()
        pasteFailedHintTimer = nil
        overlayManager.hide()
        appState.pasteFailedHint = false
    }

    /// Configure the text processing filters based on current user preferences.
    func configureFilters() {
        textProcessor.removeAllFilters()

        let defaults = UserDefaults.standard

        if defaults.bool(forKey: "removeFillerWords") {
            textProcessor.addFilter(FillerWordFilter())
        }

        if defaults.bool(forKey: "autoFormat") {
            textProcessor.addFilter(FormattingFilter())
        }

        if defaults.bool(forKey: "llmRewrite") {
            textProcessor.addFilter(LLMRewriter())
        }
    }
}
