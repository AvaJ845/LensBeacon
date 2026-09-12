#if DEBUG
import Foundation
import SwiftData

// ─────────────────────────────────────────────────────────────────────────────────
// DEVELOPER-ONLY, like `CaptureLog.swift` beside it. This whole slice — models,
// scanner, coordinator, and `Views/HarnessView.swift` — is inside `#if DEBUG`, so
// it never compiles into the Release / TestFlight / App Store binary. See
// `HARNESS.md` for what it's for and the field protocol it exists to run.
//
// It's a separate, private SwiftData store (its own file, not the App Group, not
// `SightingsStore`'s JSON log) — this is research telemetry about *the radio*,
// not a user's sightings, and it has no business sharing a container with either.
// ─────────────────────────────────────────────────────────────────────────────────

/// The three density buckets the field protocol asks the operator to log a
/// session under. Coarse on purpose — a screening variable, not something the
/// harness tries to measure precisely (no crowd-counting).
enum HarnessEnvironment: String, CaseIterable, Identifiable, Codable {
    case isolated
    case lowDensity
    case highDensity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .isolated:    return "Isolated — empty room, no other BLE traffic nearby"
        case .lowDensity:  return "Low density — a few other people/devices around"
        case .highDensity: return "High density — crowded public space"
        }
    }
}

/// Ground truth for one physical device the operator says was actually present
/// during a session — entered by hand, never inferred. A detection log with no
/// ground truth like this is uninterpretable: it can only say "a signature was
/// seen," never whether it came from what we think it did. See
/// `SessionAnalyzer.DeviceStateRecord` for why these are independent booleans.
@Model
final class DeviceState {
    var id: UUID = UUID()
    var label: String = ""
    var present: Bool = true
    var paired: Bool = false
    var worn: Bool = false
    var activelyRecording: Bool = false
    var inBagOrCase: Bool = false
    var poweredOff: Bool = false

    var session: HarnessSession?

    init(label: String = "") {
        self.id = UUID()
        self.label = label
    }

    var asRecord: DeviceStateRecord {
        DeviceStateRecord(
            label: label, present: present, paired: paired, worn: worn,
            activelyRecording: activelyRecording, inBagOrCase: inBagOrCase, poweredOff: poweredOff
        )
    }
}

// `SessionEventKind` itself lives in `SessionAnalyzer.swift`, un-gated — this
// model just wraps it in a `@Model`. It needs to compile in every
// configuration (including the always-compiled test target), same reasoning
// as `PacketRecord`/`DeviceStateRecord`.
@Model
final class SessionEvent {
    var id: UUID = UUID()
    var at: Date = Date()
    var kindRaw: String = SessionEventKind.photoCapture.rawValue

    var session: HarnessSession?

    var kind: SessionEventKind {
        get { SessionEventKind(rawValue: kindRaw) ?? .photoCapture }
        set { kindRaw = newValue.rawValue }
    }

    init(kind: SessionEventKind, at: Date = Date()) {
        self.id = UUID()
        self.at = at
        self.kindRaw = kind.rawValue
    }

    var asRecord: SessionEventRecord { SessionEventRecord(kind: kind, at: at) }
}

/// One captured BLE advertisement, exactly as CoreBluetooth reported it, with
/// nothing discarded. Classification is a **pure function over this table**
/// (`PacketClassifier`), never something computed once at capture time and
/// thrown away — a changed hypothesis must be replayable against every session
/// ever recorded without re-collecting anything.
@Model
final class RawPacket {
    var id: UUID = UUID()
    /// `Date` already carries sub-second precision; nothing here rounds it further.
    var timestamp: Date = Date()
    /// iOS's per-app peripheral UUID. **Not a hardware MAC, and not stable
    /// across sessions or reinstalls** — the OS rotates it. Recorded anyway, as
    /// the only handle available to group packets from the same peripheral
    /// *within* one session; never treated as a durable cross-session identity.
    var peripheralID: String = ""
    var rssi: Int = 0
    /// Full manufacturer-specific data (AD type 0xFF), spaced hex, company
    /// prefix first. `nil` when the advertisement carried none.
    var manufacturerDataHex: String?
    /// Company identifier decoded from the first two (little-endian) bytes of
    /// `manufacturerDataHex`. `Int`, not `UInt16` — SwiftData's native type set.
    /// `nil` whenever there were fewer than two manufacturer-data bytes to read.
    var companyIDRaw: Int?
    var serviceUUIDs: [String] = []
    var localName: String?
    var isConnectable: Bool = false
    var txPower: Int?

    var session: HarnessSession?

    var companyID: UInt16? {
        get { companyIDRaw.map { UInt16(truncatingIfNeeded: $0) } }
        set { companyIDRaw = newValue.map { Int($0) } }
    }

    init(
        timestamp: Date, peripheralID: String, rssi: Int, manufacturerDataHex: String?,
        companyID: UInt16?, serviceUUIDs: [String], localName: String?,
        isConnectable: Bool, txPower: Int?
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.peripheralID = peripheralID
        self.rssi = rssi
        self.manufacturerDataHex = manufacturerDataHex
        self.companyIDRaw = companyID.map { Int($0) }
        self.serviceUUIDs = serviceUUIDs
        self.localName = localName
        self.isConnectable = isConnectable
        self.txPower = txPower
    }

    var asRecord: PacketRecord {
        PacketRecord(
            peripheralID: peripheralID, timestamp: timestamp, rssi: rssi,
            manufacturerDataHex: manufacturerDataHex, companyID: companyID,
            serviceUUIDs: serviceUUIDs, localName: localName,
            isConnectable: isConnectable, txPower: txPower
        )
    }
}

/// One tagged field-collection run: ground truth plus every raw packet captured
/// while it was open. See `HARNESS.md` for the field protocol this is built to
/// support.
@Model
final class HarnessSession {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date?
    var environmentRaw: String = HarnessEnvironment.isolated.rawValue
    var notes: String = ""
    /// A plain, denormalized counter — kept in sync by `HarnessCoordinator
    /// .ingest` alongside every insert. Exists solely so a list row can show
    /// "how many packets" without touching `packets` below: reading a
    /// `@Relationship` array's `.count` faults (fully materializes) every
    /// related `RawPacket` into memory, which is fine to pay once when
    /// actually opening a session's Analysis screen, but was hanging the UI
    /// when `SessionListView` did it for every row just to render a number.
    var packetCount: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \DeviceState.session)
    var deviceStates: [DeviceState] = []

    @Relationship(deleteRule: .cascade, inverse: \RawPacket.session)
    var packets: [RawPacket] = []

    @Relationship(deleteRule: .cascade, inverse: \SessionEvent.session)
    var events: [SessionEvent] = []

    var environment: HarnessEnvironment {
        get { HarnessEnvironment(rawValue: environmentRaw) ?? .isolated }
        set { environmentRaw = newValue.rawValue }
    }

    var isActive: Bool { endedAt == nil }

    init(environment: HarnessEnvironment = .isolated) {
        self.id = UUID()
        self.startedAt = Date()
        self.environmentRaw = environment.rawValue
    }
}

enum HarnessStore {
    /// A private on-disk store, deliberately not the App Group container —
    /// research telemetry about the radio, unrelated to a user's sightings.
    static let container: ModelContainer = {
        let schema = Schema([HarnessSession.self, DeviceState.self, RawPacket.self, SessionEvent.self])
        let url = URL.applicationSupportDirectory.appending(path: "lensbeacon-harness.store")
        let config = ModelConfiguration(schema: schema, url: url)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Debug-only tooling: if the on-disk schema is stale from a prior
            // build, start clean rather than crash the whole app on launch.
            try? FileManager.default.removeItem(at: url)
            return try! ModelContainer(for: schema, configurations: [config])
        }
    }()
}
#endif
