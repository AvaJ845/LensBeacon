import Foundation
import Observation

/// The set of devices the user has marked "This is mine" so LensBeacon stops
/// flagging them.
///
/// Stored as a sorted list of the app's opaque peripheral keys in the App Group,
/// so the widget and a background scan honour the same suppressions. There is no
/// naming, no grouping, no cloud sync — marking a device mine is a purely local
/// "hide this from me" switch.
@MainActor
@Observable
final class MineRegistry {

    private(set) var keys: Set<String>

    init() {
        let stored = SharedContainer.defaults.stringArray(forKey: SharedContainer.Key.mineDeviceKeys) ?? []
        keys = Set(stored)
    }

    func contains(_ key: String) -> Bool { keys.contains(key) }

    func setMine(_ isMine: Bool, key: String) {
        if isMine { keys.insert(key) } else { keys.remove(key) }
        persist()
    }

    func toggle(_ key: String) {
        setMine(!keys.contains(key), key: key)
    }

    private func persist() {
        SharedContainer.defaults.set(keys.sorted(), forKey: SharedContainer.Key.mineDeviceKeys)
    }

    /// Folds in any change a background scan made while the app was suspended.
    func reload() {
        let stored = SharedContainer.defaults.stringArray(forKey: SharedContainer.Key.mineDeviceKeys) ?? []
        keys = Set(stored)
    }
}
