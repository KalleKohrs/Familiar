import SwiftUI

/// Schrift-Tokens. Alle basieren auf Dynamic-Type-Textstilen und skalieren
/// mit der Systemschriftgröße. Überschriften nutzen New York (Serif), Fließtext SF Pro.
public enum FamiliarFont {
    /// Große Bildschirmtitel (Standard 34 pt).
    public static let display = Font.system(.largeTitle, design: .serif, weight: .semibold)
    /// Abschnitts- und Sheet-Titel (Standard 22 pt).
    public static let title = Font.system(.title2, design: .serif, weight: .semibold)
    /// Gruppen-Überschriften (Standard 17 pt).
    public static let sectionTitle = Font.headline
    /// Titel in Cards (Standard 17 pt).
    public static let cardTitle = Font.body.weight(.semibold)
    public static let body = Font.body
    /// Sekundärinformationen wie Beschreibungen (Standard 15 pt).
    public static let secondary = Font.subheadline
    /// Metadaten (Standard 13 pt).
    public static let meta = Font.footnote
    public static let caption = Font.caption.weight(.medium)
    /// Uhrzeiten mit gleich breiten Ziffern.
    public static let time = Font.footnote.monospacedDigit().weight(.medium)
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
