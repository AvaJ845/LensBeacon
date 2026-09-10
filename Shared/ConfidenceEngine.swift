import Foundation

/// Turns a raw BLE advertisement into a classification plus the evidence behind it.
///
/// Pure and synchronous by design: no CoreBluetooth types cross this boundary, only
/// the handful of fields we actually reason about. That keeps the rules readable,
/// keeps them unit-testable without a Bluetooth radio, and means the "why was this
/// flagged" screen is showing the *same* structure the decision was made from.
enum ConfidenceEngine {

    /// The distilled advertisement fields the rules operate on.
    struct Advertisement: Sendable, Equatable {
        var companyIdentifier: UInt16?
        var serviceUUIDs: Set<String>
        var localName: String?
        var isConnectable: Bool
    }

    /// One matched signature and the clauses that fired for it.
    struct Evidence: Identifiable, Sendable, Equatable {
        var id: String { signatureID }
        let signatureID: String
        let productName: String
        let vendor: String
        let category: DeviceCategory
        let matched: DeviceSignature.MatchedSignals

        /// Bullet strings for the evidence list, in signal order.
        var bullets: [String] {
            var out: [String] = []
            if matched.contains(.manufacturer) {
                out.append("Manufacturer signal matches \(vendor)")
            }
            if matched.contains(.serviceUUID) {
                out.append("Advertises a service identifier used by \(productName)")
            }
            if matched.contains(.namePattern) {
                out.append("Device name matches the \(productName) pattern")
            }
            return out
        }
    }

    /// The engine's verdict for one advertisement.
    struct Classification: Sendable, Equatable {
        /// `nil` when nothing in the table matched — an ordinary nearby device.
        var category: DeviceCategory?
        /// `nil` unless `category == .cameraGlasses`.
        var confidence: ConfidenceLevel?
        /// Best human label we have: matched product name, else the advertised name,
        /// else a generic string the caller supplies.
        var productName: String?
        var vendor: String?
        /// Every signature that matched, strongest evidence first. Drives the
        /// evidence-per-flag UI.
        var evidence: [Evidence]

        static let unmatched = Classification(
            category: nil, confidence: nil, productName: nil, vendor: nil, evidence: []
        )

        /// True only for a device the app should raise to the user as a camera.
        var isCameraFlag: Bool { category == .cameraGlasses && confidence != nil }
    }

    /// Maps a matched-signal set to a confidence band.
    ///
    /// - manufacturer only .......... `possible`
    /// - manufacturer + service ..... `likely`
    /// - manufacturer + service + name  `strong`
    /// - service + name, no manufacturer  `likely` (two independent signals still agree)
    static func confidence(for matched: DeviceSignature.MatchedSignals) -> ConfidenceLevel {
        let count = [
            matched.contains(.manufacturer),
            matched.contains(.serviceUUID),
            matched.contains(.namePattern),
        ].filter { $0 }.count

        switch count {
        case 3:  return .strong
        case 2:  return .likely
        default: return .possible
        }
    }

    /// Classifies one advertisement against the signature table.
    static func classify(
        _ ad: Advertisement,
        table: [DeviceSignature] = SignatureTable.all
    ) -> Classification {
        var evidence: [Evidence] = []

        for signature in table {
            guard let matched = signature.evaluate(
                companyIdentifier: ad.companyIdentifier,
                serviceUUIDs: ad.serviceUUIDs,
                localName: ad.localName
            ) else { continue }

            evidence.append(
                Evidence(
                    signatureID: signature.id,
                    productName: signature.displayName,
                    vendor: signature.vendor,
                    category: signature.category,
                    matched: matched
                )
            )
        }

        guard !evidence.isEmpty else { return .unmatched }

        // A *distinguishing* headset match (Quest / Vision Pro identified by name or a
        // headset-specific service) always wins: worn-openly hardware must never be
        // escalated to a covert-camera flag. A headset signature that matched only on
        // a shared company ID (Meta's ID covers glasses and Quest alike) is too weak
        // to reclassify — it is dropped so a bare Meta advertisement can still surface
        // as a "possible" camera per the confidence model.
        if let headset = evidence.first(where: {
            $0.category == .headset
                && ($0.matched.contains(.namePattern) || $0.matched.contains(.serviceUUID))
        }) {
            return Classification(
                category: .headset,
                confidence: nil,
                productName: headset.productName,
                vendor: headset.vendor,
                evidence: sorted(evidence)
            )
        }

        // Otherwise take the strongest camera-glasses match.
        let cameraEvidence = evidence.filter { $0.category == .cameraGlasses }
        guard let best = cameraEvidence.max(by: {
            confidence(for: $0.matched) < confidence(for: $1.matched)
        }) else {
            return Classification(
                category: .other, confidence: nil,
                productName: nil, vendor: nil, evidence: sorted(evidence)
            )
        }

        return Classification(
            category: .cameraGlasses,
            confidence: confidence(for: best.matched),
            productName: best.productName,
            vendor: best.vendor,
            evidence: sorted(cameraEvidence)
        )
    }

    private static func sorted(_ evidence: [Evidence]) -> [Evidence] {
        evidence.sorted { confidence(for: $0.matched) > confidence(for: $1.matched) }
    }
}
