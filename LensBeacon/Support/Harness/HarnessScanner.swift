#if DEBUG
import Foundation
import CoreBluetooth

/// One captured advertisement, distilled into `Sendable` values before it
/// leaves the delegate callback.
struct HarnessAdvertisement: Sendable {
    let peripheralID: String
    let timestamp: Date
    let rssi: Int
    let manufacturerDataHex: String?
    let companyID: UInt16?
    let serviceUUIDs: [String]
    let localName: String?
    let isConnectable: Bool
    let txPower: Int?
}

/// A deliberately **promiscuous** central-role scanner: no service UUID filter,
/// `allowDuplicates: true`. This is the opposite tradeoff from the product
/// app's own `LensBeacon/Scanner/BluetoothScanner.swift`, which is filtered so
/// iOS keeps it alive in the background — this one is unfiltered so it
/// captures *everything*, which is the whole point of a measurement
/// instrument, at the cost of that same background reliability.
///
/// **Background-mode limitation, stated plainly, per the harness brief's own
/// instruction to say so loudly rather than engineer around it silently**:
/// iOS only keeps a background BLE scan running on an ongoing, reliable basis
/// when it is filtered by service UUID. An unfiltered scan like this one is
/// throttled and can be suspended once the app has been
/// backgrounded for more than a brief window — Apple documents no exact
/// cutoff, and it varies by device, iOS version, and battery state. In
/// practice: **a "pocket for hours" session is not something this scanner can
/// promise end-to-end.** There is no restart-timer or filter trick that fixes
/// this without narrowing the scan (which would defeat the harness's whole
/// purpose — a filtered scan can only ever confirm what's already in the
/// filter). Treat any multi-minute gap in a background capture as probably
/// this, not as a real absence of BLE traffic, and prefer foregrounded
/// sessions (screen on, app open) for any session where the interval-
/// distribution number actually matters.
final class HarnessScanner: NSObject {

    enum State: Equatable, Sendable { case idle, unauthorized, poweredOff, unsupported, scanning }

    // `@Sendable`, matching `BluetoothScanner.onEvent`/`onStateChange` exactly —
    // this class is a plain, non-actor-isolated delegate object (its
    // `CBCentralManager` happens to run on `queue: .main`, but nothing in the
    // type system says so), so these closures must be explicitly hopped to the
    // main actor at the call site (`HarnessCoordinator.init`), never assumed
    // safe just because they're formed inside a `@MainActor` initializer.
    var onPacket: (@Sendable (HarnessAdvertisement) -> Void)?
    var onStateChange: (@Sendable (State) -> Void)?

    private(set) var isRunning = false
    private var central: CBCentralManager?

    func start() {
        isRunning = true
        if let central {
            if central.state == .poweredOn { beginScan(central) }
        } else {
            central = CBCentralManager(
                delegate: self, queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: false]
            )
        }
    }

    func stop() {
        central?.stopScan()
        isRunning = false
    }

    private func beginScan(_ central: CBCentralManager) {
        central.scanForPeripherals(
            withServices: nil,   // promiscuous, by design — see the type doc above.
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }
}

extension HarnessScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, isRunning { beginScan(central) }
        let mapped: State
        switch central.state {
        case .poweredOn:    mapped = isRunning ? .scanning : .idle
        case .poweredOff:   mapped = .poweredOff
        case .unauthorized: mapped = .unauthorized
        case .unsupported:  mapped = .unsupported
        default:            mapped = .idle
        }
        onStateChange?(mapped)
    }

    func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi RSSI: NSNumber
    ) {
        let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        var companyID: UInt16?
        if let mfg, mfg.count >= 2 {
            companyID = UInt16(mfg[mfg.startIndex]) | (UInt16(mfg[mfg.index(after: mfg.startIndex)]) << 8)
        }
        var uuids: [String] = []
        for key in [CBAdvertisementDataServiceUUIDsKey, CBAdvertisementDataOverflowServiceUUIDsKey,
                    CBAdvertisementDataSolicitedServiceUUIDsKey] {
            if let list = advertisementData[key] as? [CBUUID] {
                uuids.append(contentsOf: list.map { $0.uuidString.uppercased() })
            }
        }
        onPacket?(HarnessAdvertisement(
            peripheralID: peripheral.identifier.uuidString,
            timestamp: Date(),
            rssi: RSSI.intValue,
            manufacturerDataHex: mfg?.map { String(format: "%02X", $0) }.joined(separator: " "),
            companyID: companyID,
            serviceUUIDs: uuids,
            localName: advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            isConnectable: (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false,
            txPower: (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue
        ))
    }
}
#endif
