import FamiliarDesign
import SwiftUI

/// Rechtstexte und Hilfe auf familiar-app.de (Quellen: `docs/legal/`, `tools/build-website.py`).
enum LegalLink {
    static let base = URL(string: "https://familiar-app.de")!
    static let help = base.appending(path: "support/")
    static let terms = base.appending(path: "nutzungsbedingungen/")
    static let privacy = base.appending(path: "datenschutz/")
    static let imprint = base.appending(path: "impressum/")
    static let contact = base.appending(path: "kontakt/")

    /// Meldeformular für rechtswidrige Inhalte (Art. 16 DSA); bei einer Aufgabe mit deren Kennung.
    static func report(taskID: UUID? = nil) -> URL {
        let url = base.appending(path: "melden/")
        guard let taskID else { return url }
        return url.appending(queryItems: [URLQueryItem(name: "ort", value: "Aufgabe \(taskID.uuidString.lowercased())")])
    }
}

/// Abschnitt „Hilfe & Rechtliches“ im Profil: Impressum und Datenschutz mit einem Tipp erreichbar
/// (§ 5 DDG, App-Store-Richtlinie 5.1.1).
struct LegalSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
            FamiliarSectionHeader("Hilfe & Rechtliches")
            VStack(spacing: 0) {
                row("Hilfe", systemImage: "questionmark.circle", url: LegalLink.help)
                divider
                row("Inhalt melden", systemImage: "exclamationmark.bubble", url: LegalLink.report())
                divider
                row("Nutzungsbedingungen", systemImage: "doc.text", url: LegalLink.terms)
                divider
                row("Datenschutz", systemImage: "hand.raised", url: LegalLink.privacy)
                divider
                row("Impressum", systemImage: "building.columns", url: LegalLink.imprint)
                divider
                NavigationLink {
                    LicensesView()
                } label: {
                    rowLabel("Open-Source-Lizenzen", systemImage: "shippingbox", trailing: "chevron.right")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("legal.licenses")
            }
            .familiarCard(padding: FamiliarSpacing.s)
        }
    }

    private var divider: some View {
        Divider().overlay(FamiliarColor.hairline)
    }

    private func row(_ title: LocalizedStringKey, systemImage: String, url: URL) -> some View {
        Link(destination: url) {
            rowLabel(title, systemImage: systemImage, trailing: "arrow.up.forward")
        }
        .accessibilityHint("Öffnet familiar-app.de")
    }

    private func rowLabel(_ title: LocalizedStringKey, systemImage: String, trailing: String) -> some View {
        HStack(spacing: FamiliarSpacing.s) {
            Image(systemName: systemImage)
                .foregroundStyle(FamiliarColor.textSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(title)
                .font(FamiliarFont.body)
                .foregroundStyle(FamiliarColor.textPrimary)
            Spacer(minLength: 0)
            Image(systemName: trailing)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FamiliarColor.textSecondary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: FamiliarSize.minimumTouchTarget)
        .contentShape(Rectangle())
    }
}

/// Lizenzhinweise der eingebundenen Open-Source-Bausteine (`Resources/Licenses.json`,
/// erzeugt mit `tools/generate-licenses.py`).
struct LicensesView: View {
    struct Entry: Decodable, Identifiable {
        let name: String
        let version: String
        let url: String
        let license: String
        let text: String
        var id: String { name }
    }

    private let entries: [Entry] = {
        guard let url = Bundle.main.url(forResource: "Licenses", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: FamiliarSpacing.s) {
                Text("Familiar nutzt diese Open-Source-Software. Wir danken den Autorinnen und Autoren.")
                    .font(FamiliarFont.secondary)
                    .foregroundStyle(FamiliarColor.textSecondary)
                ForEach(entries) { entry in
                    NavigationLink {
                        ScrollView {
                            Text(entry.text)
                                .font(.footnote.monospaced())
                                .foregroundStyle(FamiliarColor.textPrimary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(FamiliarSpacing.m)
                        }
                        .familiarScreenBackground()
                        .navigationTitle(entry.name)
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.version.isEmpty ? entry.name : "\(entry.name) \(entry.version)")
                                    .font(FamiliarFont.cardTitle)
                                    .foregroundStyle(FamiliarColor.textPrimary)
                                Text(entry.license)
                                    .font(FamiliarFont.meta)
                                    .foregroundStyle(FamiliarColor.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(FamiliarColor.textSecondary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.familiarCard)
                }
            }
            .padding(FamiliarSpacing.m)
        }
        .familiarScreenBackground()
        .navigationTitle("Open-Source-Lizenzen")
        .navigationBarTitleDisplayMode(.inline)
    }
}
