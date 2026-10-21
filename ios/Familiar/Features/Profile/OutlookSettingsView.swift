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
                case .failed(let text):
                    FamiliarErrorState(message: text) { Task { await outlook.reload() } }
                case .loaded:
                    if outlook.connections.isEmpty {
                        connectButton(title: "Mit Outlook verbinden")
                    } else {
                        ForEach(outlook.connections) { connection in
                            connectionSection(connection)
                        }
                    }
                }
            }
            .padding(FamiliarSpacing.m)
        }
        .familiarScreenBackground()
        .navigationTitle("Outlook")
        .navigationBarTitleDisplayMode(.inline)
        .task { await outlook.reload() }
        .announcesChanges(of: errorMessage)
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
                    message = String(localized: "Outlook ist verbunden. Die Termine erscheinen gleich im Kalender.")
                    await outlook.didConnect()
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
        case "access_denied", "consent_required":
            String(localized: "Die Freigabe wurde nicht erteilt. Bei Firmenkonten muss eventuell deine IT einmal zustimmen – Familiar braucht nur das Leserecht für Kalender.")
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
