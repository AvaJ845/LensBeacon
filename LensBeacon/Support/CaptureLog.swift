#if DEBUG
import Foundation
import CoreBluetooth
import Observation

// ─────────────────────────────────────────────────────────────────────────────────
// DEVELOPER-ONLY. This whole file is inside `#if DEBUG`, so it is not compiled into
// the Release / TestFlight / App Store binary. It exists for one job: capturing the
// *complete* BLE advertisement of a Meta / Snap / Even Realities device so the
// signature table (`Shared/DetectionRules.swift`) can be confirmed against real
// hardware instead of a registry lookup.
//
// It is still central-role only — it scans and reads advertisements, and never
// connects, pairs, writes, or advertises. Nothing it captures leaves the device
// except through an explicit Share sheet the user taps.
// ─────────────────────────────────────────────────────────────────────────────────

/// One complete advertisement payload, every field CoreBluetooth exposes.
struct RawAdvertisement: Codable, Equatable, Sendable {
    var rssi: Int
    var localName: String?
    var peripheralName: String?
    /// Full manufacturer-specific data, spaced hex (company ID is the first two bytes,
    /// little-endian).
    var manufacturerHex: String?
    var companyID: String?
    var serviceUUIDs: [String]
    var overflowServiceUUIDs: [String]
    var solicitedServiceUUIDs: [String]
    /// service UUID → data payload, spaced hex.
    var serviceData: [String: String]
    var txPower: Int?
    var isConnectable: Bool

    /// A stable key for "have I seen this exact payload before" (ignores RSSI).
    var fingerprint: String {
        [
            localName ?? "",
            manufacturerHex ?? "",
            serviceUUIDs.sorted().joined(separator: ","),
            serviceData.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ","),
            "\(isConnectable)",
        ].joined(separator: "|")
    }
}

/// Everything we've heard from one peripheral this session.
struct CapturedDevice: Identifiable, Codable, Sendable {
    let id: String                 // peripheral.identifier.uuidString
    var firstSeen: Date
    var lastSeen: Date
    var packetCount: Int
    var strongestRSSI: Int
    var variants: [RawAdvertisement]   // distinct payloads, newest first
    var engineVerdict: String
    /// What the tester says this device is — annotates the export.
    var userTag: String?

    var latest: RawAdvertisement? { variants.first }

    /// Does anything about this device suggest camera / display glasses?
    var isCandidate: Bool {
        guard let v = latest else { return false }
        if v.manufacturerHex != nil { return true }
        let n = (v.localName ?? "").lowercased()
        return ["ray", "oakley", "meta", "spectacles", "snap", "even", "g1", "quest",
                "oculus", "vision", "heycyan", "vista"].contains { n.contains($0) }
    }
}

@MainActor
@Observable
final class CaptureLog: NSObject {

    private(set) var devices: [CapturedDevice] = []
    private(set) var state: BluetoothScanner.State = .idle
    private(set) var isRunning = false

    private var central: CBCentralManager?
    private var byID: [String: CapturedDevice] = [:]

    // Suggested tags for the picker.
    static let tags = [
        "Ray-Ban Meta", "Oakley Meta", "Ray-Ban Display",
        "Snap Spectacles",
        "Even Realities G1 — left", "Even Realities G1 — right",
        "Even Realities G2", "Meta Quest", "Apple Vision Pro",
        "Not glasses",
    ]

    func start() {
        guard central == nil else { central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]); isRunning = true; return }
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
        isRunning = true
    }

    func stop() {
        central?.stopScan()
        isRunning = false
        publish()
    }

    func clear() {
        byID.removeAll()
        devices = []
    }

    func tag(_ id: String, _ tag: String?) {
        byID[id]?.userTag = tag
        publish()
    }

    func device(_ id: String) -> CapturedDevice? { byID[id] }

    /// Pasteable text — the whole session, or one device when `only` is set.
    func exportText(only id: String? = nil) -> String {
        let selection = id.flatMap { key in byID[key].map { [$0] } }
            ?? byID.values.sorted { ($0.userTag != nil ? 0 : 1, $0.strongestRSSI) > ($1.userTag != nil ? 0 : 1, $1.strongestRSSI) }
        var out = "LensBeacon BLE capture — \(Date().formatted(date: .abbreviated, time: .standard))\n"
        out += "\(selection.count) device(s), central-role scan, allowDuplicates.\n\n"
        for d in selection {
            out += "──────────────────────────────────────────────\n"
            out += "TAG:        \(d.userTag ?? "(untagged)")\n"
            out += "peripheral: \(d.id)\n"
            out += "seen:       \(d.packetCount) packets, strongest \(d.strongestRSSI) dBm\n"
            out += "engine:     \(d.engineVerdict)\n"
            for (i, v) in d.variants.enumerated() {
                out += "  ── advertisement variant \(i + 1) ──\n"
                out += "  name:        \(v.localName ?? "—")   (peripheral.name: \(v.peripheralName ?? "—"))\n"
                out += "  company:     \(v.companyID ?? "none")\n"
                out += "  mfg data:    \(v.manufacturerHex ?? "—")\n"
                out += "  services:    \(v.serviceUUIDs.isEmpty ? "—" : v.serviceUUIDs.joined(separator: ", "))\n"
                if !v.serviceData.isEmpty {
                    out += "  serviceData: \(v.serviceData.map { "\($0.key)={\($0.value)}" }.joined(separator: ", "))\n"
                }
                if !v.overflowServiceUUIDs.isEmpty { out += "  overflow:    \(v.overflowServiceUUIDs.joined(separator: ", "))\n" }
                if !v.solicitedServiceUUIDs.isEmpty { out += "  solicited:   \(v.solicitedServiceUUIDs.joined(separator: ", "))\n" }
                out += "  txPower:     \(v.txPower.map(String.init) ?? "—")   connectable: \(v.isConnectable)\n"
            }
            out += "\n"
        }
        return out
    }

    // MARK: - Ingest  (called on the main actor with only Sendable values)

    fileprivate func record(id: String, ad: RawAdvertisement, verdict: String) {
        let now = Date()

        var device = byID[id] ?? CapturedDevice(
            id: id, firstSeen: now, lastSeen: now, packetCount: 0,
            strongestRSSI: -200, variants: [], engineVerdict: "—"
        )
        device.lastSeen = now
        device.packetCount += 1
        device.strongestRSSI = max(device.strongestRSSI, ad.rssi)

        if let idx = device.variants.firstIndex(where: { $0.fingerprint == ad.fingerprint }) {
            device.variants[idx].rssi = ad.rssi
        } else {
            device.variants.insert(ad, at: 0)
        }
        device.engineVerdict = verdict

        byID[id] = device
        dirty = true
        schedulePublish()
    }

    // Republish to the view at ~1.5 Hz max — a raw scan sees several packets a
    // second, and reordering the list under the user's finger makes a row
    // impossible to tap. Order is fixed by first-seen so devices never jump.
    private var publishTask: Task<Void, Never>?
    private var dirty = false

    private func schedulePublish() {
        guard publishTask == nil else { return }
        publishTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(650))
                guard let self else { return }
                if self.dirty { self.dirty = false; self.publish() }
                else if !self.isRunning { self.publishTask = nil; return }
            }
        }
    }

    private func publish() {
        devices = byID.values.sorted { $0.firstSeen < $1.firstSeen }
    }

    /// Parses every CB advertisement key into Sendable values, callable from the
    /// nonisolated delegate. `peripheralName` and `rssi` are passed in already
    /// extracted so no CB type crosses into the closure.
    nonisolated static func parse(_ data: [String: Any], peripheralName: String?, rssi: Int) -> RawAdvertisement {
        let mfg = data[CBAdvertisementDataManufacturerDataKey] as? Data
        var company: String?
        if let mfg, mfg.count >= 2 {
            let v = UInt16(mfg[mfg.startIndex]) | (UInt16(mfg[mfg.index(after: mfg.startIndex)]) << 8)
            company = String(format: "0x%04X", v)
        }
        func uuids(_ key: String) -> [String] {
            ((data[key] as? [CBUUID]) ?? []).map { $0.uuidString.uppercased() }
        }
        var serviceData: [String: String] = [:]
        if let sd = data[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            for (k, v) in sd { serviceData[k.uuidString.uppercased()] = v.hexSpaced }
        }
        return RawAdvertisement(
            rssi: rssi,
            localName: (data[CBAdvertisementDataLocalNameKey] as? String),
            peripheralName: peripheralName,
            manufacturerHex: mfg?.hexSpaced,
            companyID: company,
            serviceUUIDs: uuids(CBAdvertisementDataServiceUUIDsKey),
            overflowServiceUUIDs: uuids(CBAdvertisementDataOverflowServiceUUIDsKey),
            solicitedServiceUUIDs: uuids(CBAdvertisementDataSolicitedServiceUUIDsKey),
            serviceData: serviceData,
            txPower: (data[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue,
            isConnectable: (data[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false
        )
    }
}

// MARK: - CBCentralManagerDelegate (main-queue central, so hop is trivial)

extension CaptureLog: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let poweredOn = central.state == .poweredOn
        if poweredOn {
            central.scanForPeripherals(withServices: nil,
                                       options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
        let mapped: BluetoothScanner.State
        switch central.state {
        case .poweredOn:    mapped = .scanning
        case .poweredOff:   mapped = .poweredOff
        case .unauthorized: mapped = .unauthorized
        case .unsupported:  mapped = .unsupported
        default:            mapped = .idle
        }
        MainActor.assumeIsolated { self.state = mapped }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Distil to Sendable values here, before hopping — no CB type crosses.
        let id = peripheral.identifier.uuidString
        let ad = CaptureLog.parse(advertisementData, peripheralName: peripheral.name, rssi: RSSI.intValue)
        let fields = BluetoothScanner.parse(advertisementData)
        let d = DetectionEngine.classify(fields)
        let verdict = d.matched
            ? "\(d.category.rawValue) · \(d.bestTier?.shortTitle ?? "?") — \(d.displayTitle())"
            : "no match"
        MainActor.assumeIsolated {
            guard self.isRunning else { return }
            self.record(id: id, ad: ad, verdict: verdict)
        }
    }
}

extension Data {
    var hexSpaced: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}
#endif
