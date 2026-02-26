import Foundation

extension Bundle {
    /// Resolves the SPM resource bundle for both release .app bundles and dev builds.
    ///
    /// SPM's generated `Bundle.module` looks at `Bundle.main.bundleURL` (the .app root),
    /// but signed app bundles require resources in `Contents/Resources/` — files in the
    /// bundle root cause codesign to fail with "unsealed contents". This accessor checks
    /// `Contents/Resources/` first, then falls back to SPM's generated accessor for dev.
    static let appModule: Bundle = {
        let bundleName = "Speak_Speak.bundle"

        // Release .app: resources live in Contents/Resources/
        if let resourceURL = Bundle.main.resourceURL,
           let bundle = Bundle(url: resourceURL.appendingPathComponent(bundleName)) {
            return bundle
        }

        // Dev builds: SPM's generated accessor finds the bundle via hardcoded build path
        return Bundle.module
    }()
}
