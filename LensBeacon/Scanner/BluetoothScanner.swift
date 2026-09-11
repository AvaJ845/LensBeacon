import Foundation
import CoreBluetooth
import os

/// A discovery event, distilled from a CoreBluetooth advertisement into the small
/// `Sendable` shape the rest of the app reasons about. Nothing `CB`-typed escapes
/// the scanner.
struct ScanEvent: Sendable {
    /// iOS's per-app, per-device peripheral UUID. This is **not** a hardware MAC —
    /// the OS rotates the underlying address and only hands apps this stable-ish
    /// identifier. LensBeacon treats it as an opaque local key and never tries to
    /// resolve it to anything else.
    let peripheralKey: String
    let advertisement: AdvertisementFields
    let rssi: Double
    let timestamp: Date
}

/// Thin wrapper around a single central-role `CBCentralManager`.
///
/// Responsibilities, and nothing beyond them:
///  - own the manager, on a dedicated serial queue, with a restore identifier so a
///    background relaunch resumes the same scan;
///  - translate `didDiscover` callbacks into `ScanEvent`s and forward them;
///  - surface authorization / power state as a plain enum for the UI.
///
/// Explicit non-responsibilities, enforced by never calling the APIs:
///  - never `connect`, never `discoverServices`, never read or write a characteristic;
///  - never `startAdvertising` (this app is central-only);
///  - no timers that keep the radio hot — the duty cycle is driven by the coordinator.
final class BluetoothScanner: NSObject, @unchecked Sendable {

    /// Coarse state the Dashboard needs to explain itself to the user.
    enum State: Equatable, Sendable {
        case idle
        case unauthorized
        case poweredOff
        case unsupported
        case scanning
    }

    /// Delivered on the scanner's private queue. The coordinator hops to the main
    /// actor. Declared `@Sendable` so strict concurrency is satisfied end to end.
    var onEvent: (@Sendable (ScanEvent) -> Void)?
    var onStateChange: (@Sendable (State) -> Void)?

    private let queue = DispatchQueue(label: "com.avaresearch.lensbeacon.ble", qos: .utility)
    private let log = Logger(subsystem: "com.avaresearch.lensbeacon", category: "scanner")
    private var central: CBCentralManager?

    /// The known camera-glasses service UUIDs, as `CBUUID`, used as the background
    /// scan filter. A filtered scan is the only kind iOS keeps servicing while the
    /// app is backgrounded; a `nil`-services scan there is dropped almost immediately.
    private let knownServiceUUIDs: [CBUUID] = {
        Set(DetectionRuleTable.current.serviceUUIDs16).map { CBUUID(string: $0) }
    }()

    private var wantsBackgroundMode = false

    // MARK: - Lifecycle

    /// Creates the central manager. Call once, early — if the app was relaunched into
    /// the background by CoreBluetooth, the manager must exist to receive
    /// `willRestoreState`.
    func bootstrap() {
        queue.async { [self] in
            guard central == nil else { return }
            central = CBCentralManager(
                delegate: self,
                queue: queue,
                options: [
                    CBCentralManagerOptionRestoreIdentifierKey: "com.avaresearch.lensbeacon.central",
                    // We show our own, calmer power-off copy in the Dashboard.
                    CBCentralManagerOptionShowPowerAlertKey: false,
                ]
            )
        }
    }

    /// Begins scanning if permission and power allow. `background == true` switches to
    /// the service-filtered, duplicates-suppressed scan iOS will keep alive off-screen.
    func startScanning(background: Bool) {
        queue.async { [self] in
            wantsBackgroundMode = background
            beginScanLocked()
        }
    }

    func stopScanning() {
        queue.async { [self] in
            central?.stopScan()
            emitState()
        }
    }

    /// Stops the scan and releases the manager and its delegate. Only meaningful if
    /// the owning coordinator is ever torn down and recreated; today it is
    /// app-lifetime. Breaks the scanner ⇄ `CBCentralManager` retain cycle (DE-5).
    func teardown() {
        queue.async { [self] in
            central?.stopScan()
            central?.delegate = nil
            central = nil
            onEvent = nil
            onStateChange = nil
        }
    }

    // MARK: - Scan control (queue-isolated)

    private func beginScanLocked() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let central, central.state == .poweredOn else { emitState(); return }

        let services: [CBUUID]? = wantsBackgroundMode ? knownServiceUUIDs : nil
        central.scanForPeripherals(
            withServices: services,
            options: [
                // Foreground wants repeat advertisements so RSSI smoothing and the
                // "still here / gone" logic work. Background must not — iOS coalesces
                // them anyway and duplicates there are a battery footgun.
                CBCentralManagerScanOptionAllowDuplicatesKey: !wantsBackgroundMode
            ]
        )
        log.debug("scan started (background=\(self.wantsBackgroundMode, privacy: .public))")
        onStateChange?(.scanning)
    }

    private func emitState() {
        dispatchPrecondition(condition: .onQueue(queue))
        onStateChange?(currentState)
    }

    private var currentState: State {
        guard let central else { return .idle }
        switch central.state {
        case .poweredOn:    return central.isScanning ? .scanning : .idle
        case .poweredOff:   return .poweredOff
        case .unauthorized: return .unauthorized
        case .unsupported:  return .unsupported
        default:            return .idle
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothScanner: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        emitState()
        if central.state == .poweredOn { beginScanLocked() }
    }

    /// Background relaunch. There is nothing to reconnect — this app never connects —
    /// so restoration just means "resume the scan we were doing".
    func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        log.debug("restored by CoreBluetooth in background")
        // A restored scan implies we were in background mode when killed.
        wantsBackgroundMode = true
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let ad = Self.parse(advertisementData)
        let event = ScanEvent(
            peripheralKey: peripheral.identifier.uuidString,
            advertisement: ad,
            rssi: RSSI.doubleValue,
            timestamp: Date()
        )
        onEvent?(event)
    }

    // MARK: - Advertisement parsing

    /// Extracts only the fields the detection engine uses — manufacturer bytes,
    /// 16-bit service UUIDs (both the list form and the service-data form), the local
    /// name, and connectability. Everything else in `advertisementData` is ignored.
    static func parse(_ data: [String: Any]) -> AdvertisementFields {
        let mfg = data[CBAdvertisementDataManufacturerDataKey] as? Data

        var list16: Set<String> = []
        for key in [CBAdvertisementDataServiceUUIDsKey, CBAdvertisementDataOverflowServiceUUIDsKey] {
            if let uuids = data[key] as? [CBUUID] {
                list16.formUnion(uuids.compactMap { short16($0) })
            }
        }

        var data16: Set<String> = []
        if let serviceData = data[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            data16.formUnion(serviceData.keys.compactMap { short16($0) })
        }

        let name = (data[CBAdvertisementDataLocalNameKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let connectable = (data[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false

        return AdvertisementFields(
            manufacturerData: mfg,
            serviceUUIDs16: list16,
            serviceDataUUIDs16: data16,
            localName: (name?.isEmpty == false) ? name : nil,
            isConnectable: connectable
        )
    }

    /// The 4-hex-digit short form of a 16-bit Bluetooth SIG UUID, or `nil` for a
    /// 128-bit vendor UUID (which no current rule matches on).
    private static func short16(_ uuid: CBUUID) -> String? {
        let s = uuid.uuidString.uppercased()
        return s.count == 4 ? s : nil
    }
}
