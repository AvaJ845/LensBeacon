import Foundation
import Observation

/// The set of *products* the user has marked "This is mine" so LensBeacon stops
/// flagging them.
///
/// Keyed on the resolved product identity (`Detection.productKey`, e.g.
/// `meta-glasses`), **not** on the rotating peripheral address — so marking your own
/// Ray-Ban Metas once keeps them quiet across the OS rotating their Bluetooth
/// address and across a relaunch. Stored as a sorted list in the App Group so a
/// background scan and the widget honour the same suppressions. No naming, no
/// grouping, no cloud sync.
@MainActor
@Observable
final class MineRegistry {

    private(set) var keys: Set<String>

    init() {
        keys = Set(SharedContainer.defaults.stringArray(forKey: SharedContainer.Key.mineDeviceKeys) ?? [])
    }

    func contains(productKey: String?) -> Bool {
        guard let productKey else { return false }
        return keys.contains(productKey)
    }

    func setMine(_ isMine: Bool, productKey: String?) {
        guard let productKey else { return }
        if isMine { keys.insert(productKey) } else { keys.remove(productKey) }
        persist()
    }

    func toggle(productKey: String?) {
        guard let productKey else { return }
        setMine(!keys.contains(productKey), productKey: productKey)
    }

    /// Forget every product the user marked as theirs.
    func wipeAll() {
        keys.removeAll()
        SharedContainer.defaults.removeObject(forKey: SharedContainer.Key.mineDeviceKeys)
    }

    /// Folds in any change a background scan made while the app was suspended.
    func reload() {
        keys = Set(SharedContainer.defaults.stringArray(forKey: SharedContainer.Key.mineDeviceKeys) ?? [])
    }

    private func persist() {
        SharedContainer.defaults.set(keys.sorted(), forKey: SharedContainer.Key.mineDeviceKeys)
    }
}
