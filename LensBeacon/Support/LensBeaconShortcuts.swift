import AppIntents

/// Siri phrases and the Shortcuts / Spotlight entry for LensBeacon. One action:
/// start a scan. Donated automatically so "Hey Siri, scan for camera glasses" and
/// the Action button work with no setup.
struct LensBeaconShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartScanIntent(),
            phrases: [
                "Scan for camera glasses with \(.applicationName)",
                "Start a \(.applicationName) scan",
                "Check for camera glasses with \(.applicationName)",
                "Open \(.applicationName)"
            ],
            shortTitle: "Scan for camera glasses",
            systemImageName: "dot.radiowaves.left.and.right"
        )
    }
}
