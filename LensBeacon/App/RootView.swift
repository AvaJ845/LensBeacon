import SwiftUI

/// Two tabs. That is the whole app: what's nearby now, and what's been seen. Settings
/// is a toolbar button, not a third tab, because it is visited rarely.
struct RootView: View {

    /// Named `Screen`, not `Tab`, to avoid colliding with SwiftUI's own `Tab` type.
    enum Screen: Hashable { case dashboard, sightings }

    @Environment(Router.self) private var router
    @Environment(ScanCoordinator.self) private var coordinator
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            Tab("Nearby", systemImage: "dot.radiowaves.left.and.right", value: Screen.dashboard) {
                DashboardView()
            }
            Tab("Sightings", systemImage: "list.bullet.rectangle", value: Screen.sightings) {
                SightingsView()
            }
        }
        .onChange(of: router.pendingSightingKey) { _, key in
            guard key != nil else { return }
            router.selectedTab = .sightings
        }
        .onOpenURL { url in
            // `lensbeacon://sightings` / `lensbeacon://nearby` — a hostile link can
            // only switch tabs. Nothing is parsed, fetched or written.
            switch url.host {
            case "sightings": router.selectedTab = .sightings
            default:          router.selectedTab = .dashboard
            }
        }
    }
}
