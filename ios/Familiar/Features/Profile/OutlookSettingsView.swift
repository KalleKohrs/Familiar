import AuthenticationServices
import FamiliarCore
import FamiliarDesign
import SwiftUI

/// Outlook verbinden, Kalender wählen, trennen (Phase 8, Plan Abschnitt 7).
/// Persönlich: Termine erscheinen nur im eigenen Kalender, nie bei der Familie; Familiar liest nur.
struct OutlookSettingsView: View {
    @Environment(OutlookStore.self) private var outlook
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var isConnecting = false
    @State private var isWorking = false
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var connectionToRemove: CalendarConnection?
    /// Microsoft hat „Genehmigung erforderlich“ o. Ä. gemeldet: IT-Hinweis hervorheben.
    @State private var needsITApproval = false
    @State private var itRequest: ITApprovalRequest?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FamiliarSpacing.l) {
                Text("Deine Outlook-Termine erscheinen nur in deinem Kalender – nie bei der Familie. Familiar liest nur und ändert nichts in Outlook. Aus Terminen werden keine Aufgaben.")
                    .font(FamiliarFont.secondary)
                    .foregroundStyle(FamiliarColor.textSecondary)

                if let errorMessage {
                    FamiliarInlineError(errorMessage)
                }
                if let message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(FamiliarFont.secondary)
                        .foregroundStyle(FamiliarColor.success)
                }

                switch outlook.state {
                case .idle, .loading:
                    FamiliarSkeleton(height: 120)
                        .transition(FamiliarMotion.contentTransition)
                case .failed(let text):
                    FamiliarErrorState(message: text) { Task { await outlook.reload() } }
                case .loaded:
                    if outlook.connections.isEmpty {
                        connectButton(title: "Mit Outlook verbinden")
                        itApprovalHint
                    } else {
                        ForEach(outlook.connections) { connection in
                            connectionSection(connection)
                        }
                    }
                }
            }
            .familiarContentSwap(value: outlook.state)
            .padding(FamiliarSpacing.m)
        }
        .familiarScreenBackground()
        .navigationTitle("Outlook")
        .navigationBarTitleDisplayMode(.inline)
        .task { await outlook.reload() }
        .announcesChanges(of: errorMessage)
        .sheet(item: $itRequest) { request in
            ITApprovalSheet(request: request)
        }
        .sheet(item: $connectionToRemove) { connection in
            FamiliarChoiceSheet(
                systemImage: "calendar.badge.minus", tint: FamiliarColor.danger,
                title: "Outlook trennen?",
                message: "Familiar vergisst den Zugang und alle zwischengespeicherten Termine. In Outlook selbst ändert sich nichts."
            ) {
                Button("Trennen", role: .destructive) {
                    connectionToRemove = nil
                    run { () async throws(FamiliarError) in try await outlook.disconnect(connection) }
                }
                .buttonStyle(.familiarDestructive)
                .accessibilityIdentifier("outlook.disconnectConfirm")
            }
        }
    }

    // MARK: Verbindung

    private func connectionSection(_ connection: CalendarConnection) -> some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.m) {
            VStack(alignment: .leading, spacing: FamiliarSpacing.xxs) {
                Text(connection.accountEmail ?? String(localized: "Outlook-Konto"))
                    .font(FamiliarFont.cardTitle)
                    .foregroundStyle(FamiliarColor.textPrimary)
                Text(statusText(connection))
                    .font(FamiliarFont.meta)
                    .foregroundStyle(connection.status == .active ? FamiliarColor.textSecondary : FamiliarColor.danger)
            }

            if connection.status != .active {
                connectButton(title: "Neu anmelden")
            }

            if !connection.calendars.isEmpty {
                VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
                    FamiliarSectionHeader("Angezeigte Kalender")
                    VStack(spacing: 0) {
                        ForEach(Array(connection.calendars.enumerated()), id: \.element.id) { index, calendar in
                            Toggle(isOn: selectionBinding(calendar)) {
                                HStack(spacing: FamiliarSpacing.xs) {
                                    Image(systemName: "calendar")
                                        .foregroundStyle(FamiliarColor.textSecondary)
                                        .accessibilityHidden(true)
                                    Text(calendar.name)
                                        .font(FamiliarFont.body)
                                }
                            }
                            .tint(FamiliarColor.success)
                            .disabled(isWorking)
                            .padding(.vertical, FamiliarSpacing.xs)
                            .accessibilityIdentifier("outlook.calendar.\(calendar.name)")
                            if index < connection.calendars.count - 1 {
                                Divider().overlay(FamiliarColor.hairline)
                            }
                        }
                    }
                    .familiarCard(padding: FamiliarSpacing.m)
                }
            }

            Button {
                run { () async throws(FamiliarError) in
                    let started = try await outlook.syncNow()
                    message = started
                        ? String(localized: "Abgleich gestartet.")
                        : String(localized: "Gerade erst abgeglichen – bitte in ein paar Minuten erneut.")
                }
            } label: {
                Label("Jetzt abgleichen", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.familiarSecondary)
            .disabled(isWorking || connection.status != .active)

            Button("Outlook trennen", role: .destructive) { connectionToRemove = connection }
                .buttonStyle(.familiarDestructive)
                .disabled(isWorking)
                .accessibilityIdentifier("outlook.disconnect")
        }
    }

    private func statusText(_ connection: CalendarConnection) -> String {
        switch connection.status {
        case .needsReauth:
            return String(localized: "Anmeldung abgelaufen – bitte neu anmelden.")
        case .error:
            return String(localized: "Abgleich fehlgeschlagen.")
        case .active:
            guard let last = connection.lastSyncAt else { return String(localized: "Erster Abgleich läuft …") }
            let relative = last.formatted(.relative(presentation: .named))
            if connection.lastError == "no_mailbox" {
                return String(localized: "Zu diesem Microsoft-Konto gibt es keinen Outlook-Kalender. Trenne die Verbindung und melde dich mit dem Konto an, in dem deine Termine liegen (z. B. …@outlook.com).")
            }
            if let error = connection.lastError, !error.isEmpty {
                return String(localized: "Zuletzt versucht \(relative) – Outlook antwortete nicht.")
            }
            return String(localized: "Zuletzt abgeglichen \(relative)")
        }
    }

    private func selectionBinding(_ calendar: ExternalCalendar) -> Binding<Bool> {
        Binding {
            calendar.isSelected
        } set: { selected in
            run { () async throws(FamiliarError) in try await outlook.setSelected(calendar, selected) }
        }
    }

    // MARK: Firmenkonten

    /// Firmenkonten brauchen oft eine einmalige Freigabe durch die IT (Familiar ist kein bei
    /// Microsoft verifizierter Herausgeber). Private Outlook-Konten gehen ohne.
    private var itApprovalHint: some View {
        VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
            Label {
                VStack(alignment: .leading, spacing: FamiliarSpacing.xxs) {
                    Text(needsITApproval ? "Deine Firma muss Familiar freigeben" : "Firmenkonto?")
                        .font(FamiliarFont.cardTitle)
                        .foregroundStyle(FamiliarColor.textPrimary)
                    Text(needsITApproval
                         ? "Microsoft verlangt bei deinem Firmenkonto eine einmalige Freigabe durch die IT. Schick ihr den Link – danach kannst du Outlook verbinden."
                         : "Bei manchen Firmen muss die IT Familiar einmal freigeben. Erscheint „Genehmigung erforderlich“, schick ihr einfach den Freigabe-Link.")
                        .font(FamiliarFont.secondary)
                        .foregroundStyle(FamiliarColor.textSecondary)
                }
            } icon: {
                Image(systemName: "building.2")
                    .foregroundStyle(needsITApproval ? FamiliarColor.warning : FamiliarColor.textSecondary)
            }
            Button(action: prepareITRequest) {
                Label("Freigabe bei meiner IT anfragen", systemImage: "paperplane")
            }
            .buttonStyle(needsITApproval ? .familiarPrimary : .familiarSecondary)
            .disabled(isWorking)
            .accessibilityIdentifier("outlook.askIT")
        }
        .familiarCard()
    }

    private func prepareITRequest() {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            if let url = await outlook.loadAdminConsentURL() {
                itRequest = ITApprovalRequest(consentURL: url)
            } else {
                errorMessage = String(localized: "Der Freigabe-Link konnte nicht geladen werden. Bitte versuche es erneut.")
            }
        }
    }

    // MARK: Anmelden

    private func connectButton(title: LocalizedStringKey) -> some View {
        Button(action: connect) {
            HStack(spacing: FamiliarSpacing.xs) {
                if isConnecting { ProgressView().tint(FamiliarColor.onAccent) }
                Text(title)
            }
        }
        .buttonStyle(.familiarPrimary)
        .disabled(isConnecting)
        .accessibilityIdentifier("outlook.connect")
    }

    private func connect() {
        isConnecting = true
        errorMessage = nil
        message = nil
        Task {
            defer { isConnecting = false }
            do {
                let url = try await outlook.connectURL()
                // Normale Browser-Sitzung, damit eine bestehende Firmen-Anmeldung (SSO) genutzt wird.
                let callback = try await webAuthenticationSession.authenticate(
                    using: url,
                    callback: .customScheme("familiar"),
                    preferredBrowserSession: nil,
                    additionalHeaderFields: [:]
                )
                let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let status = items.first { $0.name == "status" }?.value
                let reason = items.first { $0.name == "reason" }?.value
                if status == "connected" {
                    needsITApproval = false
                    message = String(localized: "Outlook ist verbunden. Die Termine erscheinen gleich im Kalender.")
                    await outlook.didConnect()
                } else if reason == "admin_consent" || reason == "declined" {
                    // Firmenkonto: statt eines Fehlers den Weg über die IT zeigen.
                    needsITApproval = true
                } else {
                    errorMessage = Self.message(forReason: reason)
                }
            } catch let error as FamiliarError {
                errorMessage = error.message
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                // Abgebrochen: kein Hinweis nötig.
            } catch {
                errorMessage = String(localized: "Outlook konnte nicht verbunden werden.")
            }
        }
    }

    static func message(forReason reason: String?) -> String {
        switch reason {
        case "expired":
            String(localized: "Die Anmeldung hat zu lange gedauert. Bitte versuche es erneut.")
        default:
            String(localized: "Outlook konnte nicht verbunden werden (\(reason ?? "unbekannt")).")
        }
    }

    private func run(_ action: @escaping () async throws(FamiliarError) -> Void) {
        isWorking = true
        errorMessage = nil
        message = nil
        Task {
            defer { isWorking = false }
            do throws(FamiliarError) {
                try await action()
            } catch {
                errorMessage = error.message
            }
        }
    }
}

/// Nachricht an die IT mit Freigabe-Link (Vorschau, dann Teilen).
struct ITApprovalRequest: Identifiable {
    let consentURL: URL
    var id: URL { consentURL }

    var text: String {
        String(localized: """
        Hallo,

        ich möchte in der Familien-App „Familiar“ meine eigenen Outlook-Termine anzeigen lassen. Dafür braucht Familiar eine einmalige Freigabe für unser Unternehmen.

        Angefragte Rechte (delegiert, nur für die jeweils angemeldete Person): Calendars.ReadBasic, offline_access, openid, email. Familiar liest nur Titel, Zeit, Ort und Organisator von Terminen, ohne Termin-Text und Anhänge, und schreibt nie in Outlook.

        Freigabe-Link (als Administrator öffnen):
        \(consentURL.absoluteString)

        Weitere Infos: https://familiar-app.de/outlook-it

        Vielen Dank!
        """)
    }
}

private struct ITApprovalSheet: View {
    let request: ITApprovalRequest

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FamiliarSpacing.m) {
                    Text("Diese Nachricht kannst du per Mail oder Teams an deine IT schicken. Sie enthält den Freigabe-Link und erklärt, was Familiar liest.")
                        .font(FamiliarFont.secondary)
                        .foregroundStyle(FamiliarColor.textSecondary)
                    Text(request.text)
                        .font(FamiliarFont.body)
                        .foregroundStyle(FamiliarColor.textPrimary)
                        .textSelection(.enabled)
                        .padding(FamiliarSpacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(FamiliarColor.sunken))
                    ShareLink(item: request.text, subject: Text("Freigabe für Familiar (Outlook-Kalender)")) {
                        Label("Nachricht teilen", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.familiarPrimary)
                }
                .padding(FamiliarSpacing.m)
            }
            .familiarScreenBackground()
            .navigationTitle("An deine IT")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
    }
}
