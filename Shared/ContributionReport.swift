import Foundation

/// What a user contributing a sighting believes the device actually is. Kept to
/// the products `DetectionRuleTable` already knows how to name — free text would
/// invite spam/noise into what's meant to be a short, actionable report.
enum DeviceGuess: String, CaseIterable, Identifiable {
    case rayBanMeta = "Ray-Ban Meta"
    case oakleyMeta = "Oakley Meta"
    case snapSpectacles = "Snap Spectacles"
    case evenRealities = "Even Realities"
    case otherCameraGlasses = "Other camera glasses"
    case notSure = "Not sure"

    var id: String { rawValue }
}

/// Builds the plain-text report behind "Suggest what this is". This is the whole
/// feature: LensBeacon still makes no network request of any kind (see
/// PRIVACY.md) — the text is handed to the system Share Sheet, and the user
/// picks where it goes (Mail, Messages, Notes, AirDrop, ...) exactly like CSV
/// export already works. The app never transmits anything itself.
enum ContributionReport {
    static func text(for fields: AdvertisementFields, detection: Detection, guess: DeviceGuess?) -> String {
        var lines = ["LensBeacon — device signature suggestion", ""]

        lines.append("Advertised name: \(fields.localName?.isEmpty == false ? fields.localName! : "(none)")")
        if let company = fields.companyIdentifier {
            lines.append(String(format: "Manufacturer ID: 0x%04X", company))
        } else {
            lines.append("Manufacturer ID: (none)")
        }
        if let mfg = fields.manufacturerData, !mfg.isEmpty {
            lines.append("Manufacturer data (hex): \(mfg.map { String(format: "%02X", $0) }.joined(separator: " "))")
        }
        if !fields.serviceUUIDs16.isEmpty {
            lines.append("Service UUIDs: \(fields.serviceUUIDs16.sorted().joined(separator: ", "))")
        }
        if !fields.serviceDataUUIDs16.isEmpty {
            lines.append("Service-data UUIDs: \(fields.serviceDataUUIDs16.sorted().joined(separator: ", "))")
        }
        lines.append("Connectable: \(fields.isConnectable ? "yes" : "no")")
        lines.append("")

        lines.append("Current classification: \(currentClassification(detection))")
        if let guess {
            lines.append("What the reporter believes this is: \(guess.rawValue)")
        }

        lines.append("")
        lines.append("— Sent from LensBeacon. This device's Bluetooth identifier rotates on its "
            + "own and cannot be used to track it; nothing about the reporter's phone, identity, "
            + "or location is included.")
        return lines.joined(separator: "\n")
    }

    private static func currentClassification(_ detection: Detection) -> String {
        guard let tier = detection.bestTier else { return "unmatched — no rule in the table matched this" }
        return "\(detection.displayTitle()) (\(tier.title))"
    }
}
