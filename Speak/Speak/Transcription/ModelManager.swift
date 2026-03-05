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

    /// Ensure the speech model for the given locale is available.
    /// Creates a temporary transcriber to check and download if necessary.
    func ensureModelAvailable(for locale: Locale) async throws {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        try await ensureModelAvailable(for: transcriber)
        try? await reserveLocale(locale)
    }

    /// Pin the locale's model so macOS won't evict it.
    func reserveLocale(_ locale: Locale) async throws {
        let reserved = await AssetInventory.reservedLocales
        if reserved.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            return
        }
        let max = AssetInventory.maximumReservedLocales
        if reserved.count >= max {
            for old in reserved {
                _ = try await AssetInventory.release(reservedLocale: old)
                break
            }
        }
        _ = try await AssetInventory.reserve(locale: locale)
    }

    /// Unpin a previously reserved locale.
    func releaseLocale(_ locale: Locale) async throws {
        _ = try await AssetInventory.release(reservedLocale: locale)
    }

    /// Request speech recognition authorization.
    nonisolated func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static var authorizationGranted: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    static var authorizationNotDetermined: Bool {
        SFSpeechRecognizer.authorizationStatus() == .notDetermined
    }
}
