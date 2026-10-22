import SwiftUI
import UIKit

/// Darstellung der App: folgt dem System oder ist fest hell/dunkel. Nur auf diesem Gerät
/// gespeichert (`@AppStorage`), keine Server-Daten.
enum Appearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearance"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Setzt die Darstellung direkt an allen Fenstern. Anders als `preferredColorScheme` wirkt das
    /// sofort auch in bereits geöffneten Blättern (dort blieb „System“ sonst im alten Modus hängen).
    @MainActor
    func apply() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = interfaceStyle
            }
        }
    }
}
