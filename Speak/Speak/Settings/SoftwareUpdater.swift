import Sparkle
import SwiftUI

struct CheckForUpdatesView: View {
    let updater: SPUUpdater
    @State private var canCheckForUpdates = false

    var body: some View {
        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
        .disabled(!canCheckForUpdates)
        .task {
            while !Task.isCancelled {
                canCheckForUpdates = updater.canCheckForUpdates
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
