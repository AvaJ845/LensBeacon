import SwiftUI
import os

/// Light / Dark / System override for the whole app. Stored in the App Group so it
/// is one preference; applied with `.preferredColorScheme` at the scene root.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    static var current: AppAppearance {
        AppAppearance(rawValue: SharedContainer.defaults.string(forKey: SharedContainer.Key.appearance) ?? "")
            ?? .system
    }
}

/// The three app-icon looks. `classic` is the primary icon; the other two are
/// alternates in the asset catalog (`AppIcon-Midnight`, `AppIcon-Mono`).
enum AppIconOption: String, CaseIterable, Identifiable {
    case classic, midnight, mono
    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic:  return "Classic"
        case .midnight: return "Midnight"
        case .mono:     return "Mono"
        }
    }

    /// `nil` for the primary icon.
    var alternateName: String? {
        switch self {
        case .classic:  return nil
        case .midnight: return "AppIcon-Midnight"
        case .mono:     return "AppIcon-Mono"
        }
    }

    /// A swatch colour for the picker, so the option reads without loading the
    /// (unloadable at runtime) app-icon asset.
    var swatch: Color {
        switch self {
        case .classic:  return Palette.beaconBlue
        case .midnight: return Palette.deepNavy
        case .mono:     return Palette.lensCyan
        }
    }

    @MainActor
    static var current: AppIconOption {
        let name = UIApplication.shared.alternateIconName
        return AppIconOption.allCases.first { $0.alternateName == name } ?? .classic
    }
}

enum IconSwitcher {
    private static let log = Logger(subsystem: "com.avaresearch.lensbeacon", category: "appicon")

    @MainActor
    static func apply(_ option: AppIconOption) {
        guard UIApplication.shared.supportsAlternateIcons,
              option.alternateName != UIApplication.shared.alternateIconName
        else { return }
        UIApplication.shared.setAlternateIconName(option.alternateName) { error in
            if let error {
                log.error("alternate icon failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
