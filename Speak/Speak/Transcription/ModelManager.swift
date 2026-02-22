import Speech

@MainActor
final class ModelManager {
    /// Check if a locale is supported by SpeechTranscriber.
    func isSupported(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }

    /// Check if the model for a locale is already installed on-device.
    func isInstalled(locale: Locale) async -> Bool {
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }

    /// Ensure the speech model for the given transcriber's locale is available.
    /// Downloads it if necessary.
    func ensureModelAvailable(for transcriber: SpeechTranscriber) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            try await request.downloadAndInstall()
        }
    }

    /// Request speech recognition authorization.
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static var authorizationGranted: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }
}
