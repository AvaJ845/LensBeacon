import SwiftUI
import UserNotifications

@main
struct LensBeaconApp: App {

    // One owner each. `SightingsStore` and `MineRegistry` are built in `init` first
    // because the coordinator holds `unowned` references to them for the app's life.
    @State private var sightings: SightingsStore
    @State private var mine: MineRegistry
    @State private var coordinator: ScanCoordinator
    @State private var unlock = UnlockStore()
    @State private var router = Router.shared

    private let notifier = FlagNotifier()

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SharedContainer.Key.onboarded, store: SharedContainer.defaults)
    private var onboarded = false

    init() {
        let sightings = SightingsStore()
        let mine = MineRegistry()
        _sightings = State(initialValue: sightings)
        _mine = State(initialValue: mine)
        _coordinator = State(initialValue: ScanCoordinator(sightings: sightings, mine: mine))
    }

    /// QA / screenshot launch arguments (Release-safe — they only skip the intro or
    /// pre-seed the log; they never fabricate a live scan result).
    private var skipOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains("-skip-onboarding")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if onboarded || skipOnboarding {
                    RootView()
                } else {
                    OnboardingView(onFinish: { onboarded = true })
                }
            }
            .environment(sightings)
            .environment(mine)
            .environment(unlock)
            .environment(coordinator)
            .environment(router)
            .tint(Palette.accent)
            .task {
                UNUserNotificationCenter.current().delegate = notifier
                coordinator.onNewFlag = { sighting in
                    Haptics.firstFlag()
                    notifier.notify(about: sighting)
                }
                coordinator.bootstrap()
                await unlock.load()
                applyRetention()
                if onboarded { coordinator.startScanning() }
            }
            .onChange(of: unlock.isUnlocked) { _, _ in applyRetention() }
            .onChange(of: scenePhase) { _, phase in
                coordinator.applyScenePhase(active: phase == .active)
                if phase == .background { sightings.saveNow() }
            }
        }
    }

    /// Free tier keeps 7 days of history; Unlock keeps everything.
    private func applyRetention() {
        sightings.retention = unlock.isUnlocked ? .unlimited : .days(7)
        sightings.pruneNow()
    }
}
