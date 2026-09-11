import SwiftUI

@main
struct LensBeaconWatchApp: App {

    @State private var model = WatchScanModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
                .task { model.start() }
                .onChange(of: scenePhase) { _, phase in
                    // The watch only scans while its screen is showing LensBeacon —
                    // there is no background-scan story here, and that is the honest
                    // behaviour to present.
                    if phase == .active { model.start() } else { model.stop() }
                }
        }
    }
}
