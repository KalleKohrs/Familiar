import CoreText
import SwiftUI

/// Eigene Schrift für Überschriften, Titel und Zahlen: Bricolage Grotesque (variabel, mit optischen
/// Größen; SIL Open Font License, siehe Resources/Fonts). Fließtext bleibt SF Pro für beste Lesbarkeit.
/// Bewusst keine Standard-Serifen/Systemschrift für Überschriften – Familiar soll eigenständig wirken.
public enum FamiliarTypeface {
    public static let family = "Bricolage Grotesque"

    /// Einmal beim Start aufrufen (App, Widget-Extension, Previews).
    public static func register() {
        guard let url = Bundle.module.url(forResource: "BricolageGrotesque", withExtension: "ttf",
                                          subdirectory: "Fonts")
                ?? Bundle.module.url(forResource: "BricolageGrotesque", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    /// Skaliert mit Dynamic Type relativ zum Textstil.
    public static func font(size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight) -> Font {
        Font.custom(family, size: size, relativeTo: style).weight(weight)
    }
}

/// Schrift-Tokens. Alle skalieren mit der Systemschriftgröße (Dynamic Type).
public enum FamiliarFont {
    /// Große Bildschirmtitel.
    public static let display = FamiliarTypeface.font(size: 36, relativeTo: .largeTitle, weight: .bold)
    /// Abschnitts- und Sheet-Titel.
    public static let title = FamiliarTypeface.font(size: 24, relativeTo: .title2, weight: .semibold)
    /// Gruppen-Überschriften.
    public static let sectionTitle = FamiliarTypeface.font(size: 17, relativeTo: .headline, weight: .semibold)
    /// Titel in Cards.
    public static let cardTitle = FamiliarTypeface.font(size: 18, relativeTo: .body, weight: .semibold)
    public static let body = Font.body
    /// Sekundärinformationen wie Beschreibungen (Standard 15 pt).
    public static let secondary = Font.subheadline
    /// Metadaten (Standard 13 pt).
    public static let meta = Font.footnote
    public static let caption = Font.caption.weight(.medium)
    /// Uhrzeiten mit gleich breiten Ziffern.
    public static let time = Font.footnote.monospacedDigit().weight(.medium)
    /// Kleine Überschriften über Listenabschnitten („Heute“, „Morgen“) – ohne Versalien und Sperrung.
    public static let groupLabel = FamiliarTypeface.font(size: 15, relativeTo: .subheadline, weight: .semibold)
}

public enum FamiliarSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 12
    public static let m: CGFloat = 16
    public static let l: CGFloat = 20
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

public enum FamiliarRadius {
    public static let card: CGFloat = 24
    public static let control: CGFloat = 16
    public static let chip: CGFloat = 12
}

public enum FamiliarSize {
    /// Mindestgröße interaktiver Flächen laut Human Interface Guidelines.
    public static let minimumTouchTarget: CGFloat = 44
}
