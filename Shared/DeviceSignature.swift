import Foundation

/// What a device *is*, once we have classified it.
///
/// `headset` exists so a Quest or a Vision Pro — which broadcast plenty of BLE and
/// carry cameras — are logged and identified but **never** flagged as covert camera
/// glasses. They are worn openly and obviously; surfacing them as a "camera nearby"
/// alert would be crying wolf.
enum DeviceCategory: String, Codable, Sendable, CaseIterable {
    /// Ray-Ban Meta, Oakley Meta, Snap Spectacles and similar — the app's actual subject.
    case cameraGlasses
    /// Quest / Vision Pro / other MR headsets. Identified, listed, never alerted on.
    case headset
    /// Everything else that advertises BLE — phones, watches, earbuds, TVs, tags, beacons.
    case other
}

/// A single rule that fingerprints a BLE advertisement.
///
/// A signature is intentionally small: some combination of a manufacturer/company ID,
/// zero or more 16-bit service UUIDs, and an optional case-insensitive substring the
/// advertised local name must contain. `matchedSignals` reports *which* of those
/// actually fired for a given advertisement, and that set is what the confidence
/// engine and the "evidence per flag" UI are built from.
struct DeviceSignature: Identifiable, Sendable {

    /// Which of a signature's clauses matched a live advertisement. This is the
    /// evidence — every flag in the UI can point at exactly these.
    struct MatchedSignals: OptionSet, Sendable {
        let rawValue: Int
        static let manufacturer = MatchedSignals(rawValue: 1 << 0)
        static let serviceUUID  = MatchedSignals(rawValue: 1 << 1)
        static let namePattern  = MatchedSignals(rawValue: 1 << 2)
    }

    let id: String
    /// Human-facing product/family name, e.g. "Ray-Ban Meta". Shown only in the app
    /// body, never baked into asset names or screenshots (see the App Review notes).
    let displayName: String
    let vendor: String
    let category: DeviceCategory

    /// Bluetooth SIG company identifier (little-endian 16-bit prefix of the
    /// manufacturer-specific data), if the vendor advertises one we can rely on.
    let companyIdentifier: UInt16?
    /// 16-bit service UUIDs the product's companion protocol advertises.
    let serviceUUIDs: Set<String>
    /// Case-insensitive substring the advertised local name must contain.
    let namePatterns: [String]

    /// Evaluates this signature against one advertisement.
    ///
    /// The manufacturer clause is treated as a *filter*, not a requirement: if the
    /// advertisement carries manufacturer data and it names a different company, the
    /// signature is rejected outright (`nil`). If the advertisement carries no
    /// manufacturer data at all, the other clauses may still carry a match — a lot of
    /// real advertisements omit the company ID.
    ///
    /// - Returns: the set of clauses that matched, or `nil` if nothing matched or the
    ///   manufacturer data actively contradicted this signature.
    func evaluate(
        companyIdentifier adCompany: UInt16?,
        serviceUUIDs adServices: Set<String>,
        localName adName: String?
    ) -> MatchedSignals? {
        var matched: MatchedSignals = []

        if let companyIdentifier, let adCompany {
            guard adCompany == companyIdentifier else { return nil }
            matched.insert(.manufacturer)
        }

        if !serviceUUIDs.isEmpty {
            let hit = adServices.contains { candidate in
                serviceUUIDs.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
            }
            if hit { matched.insert(.serviceUUID) }
        }

        if !namePatterns.isEmpty, let adName, !adName.isEmpty {
            let lowered = adName.lowercased()
            if namePatterns.contains(where: { lowered.contains($0.lowercased()) }) {
                matched.insert(.namePattern)
            }
        }

        // A signature with no manufacturer clause still needs *something* to have
        // matched, or it is not a detection.
        return matched.isEmpty ? nil : matched
    }
}

/// The maintained catalogue of device signatures.
///
/// This is the one part of the app that is expected to change between releases as
/// vendors ship new hardware and revise their advertisements. It is plain data with
/// no I/O so it stays trivially testable and reviewable.
///
/// The identifiers below are the publicly documented Bluetooth SIG company IDs and
/// the service UUIDs these products are observed to advertise while unpaired. They
/// are fingerprints of a *broadcast*, not of a person: BLE MAC addresses are
/// rotated by the OS on both ends and LensBeacon neither stores nor tries to defeat
/// that rotation.
enum SignatureTable {

    /// Company identifiers referenced below, named for readability.
    private enum Company {
        /// Meta Platforms / Facebook. Used by Ray-Ban Meta and Oakley Meta, and also
        /// by Meta's other accessories — hence "manufacturer alone = possible".
        static let meta: UInt16 = 0x03A3
        /// Snap Inc. — Spectacles.
        static let snap: UInt16 = 0x0819
    }

    static let all: [DeviceSignature] = [
        DeviceSignature(
            id: "rayban-meta",
            displayName: "Ray-Ban Meta",
            vendor: "Meta",
            category: .cameraGlasses,
            companyIdentifier: Company.meta,
            serviceUUIDs: ["FDF0", "FE9F"],
            namePatterns: ["ray-ban", "rayban", "meta view", "meta glasses"]
        ),
        DeviceSignature(
            id: "oakley-meta",
            displayName: "Oakley Meta",
            vendor: "Meta",
            category: .cameraGlasses,
            companyIdentifier: Company.meta,
            serviceUUIDs: ["FDF0", "FE9F"],
            namePatterns: ["oakley", "oakley meta", "vanguard"]
        ),
        DeviceSignature(
            id: "snap-spectacles",
            displayName: "Snap Spectacles",
            vendor: "Snap",
            category: .cameraGlasses,
            companyIdentifier: Company.snap,
            serviceUUIDs: ["FE60"],
            namePatterns: ["spectacles", "snap"]
        ),
        // --- Logged, never flagged as covert cameras -------------------------------
        DeviceSignature(
            id: "meta-quest",
            displayName: "Meta Quest",
            vendor: "Meta",
            category: .headset,
            companyIdentifier: Company.meta,
            serviceUUIDs: [],
            namePatterns: ["quest"]
        ),
        DeviceSignature(
            id: "apple-vision-pro",
            displayName: "Apple Vision Pro",
            vendor: "Apple",
            category: .headset,
            companyIdentifier: 0x004C,
            serviceUUIDs: [],
            namePatterns: ["vision pro"]
        ),
    ]

    /// Signatures that, when matched, produce a camera-glasses flag.
    static var cameraGlasses: [DeviceSignature] {
        all.filter { $0.category == .cameraGlasses }
    }
}
