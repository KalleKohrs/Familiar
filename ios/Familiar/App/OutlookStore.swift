import FamiliarCore
import Foundation
import Observation

/// Persönliche Outlook-Verbindung (Phase 8): Status, Kalenderauswahl und Termine für den Kalender.
/// Alles ist strikt persönlich – Familienmitglieder sehen diese Termine nie.
@Observable
final class OutlookStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var connections: [CalendarConnection] = []
    private(set) var state: LoadState = .idle
    /// Ändert sich, wenn Termine neu geladen werden sollten (Kalender nachladen).
    private(set) var revision = 0

    private let repository: any ExternalCalendarRepository

    init(repository: any ExternalCalendarRepository) {
        self.repository = repository
    }

    var isConnected: Bool { !connections.isEmpty }

    func reload() async {
        if state == .idle { state = .loading }
        do throws(FamiliarError) {
            connections = try await repository.connections()
            state = .loaded
        } catch {
            state = .failed(error.message)
        }
    }

    func connectURL() async throws(FamiliarError) -> URL {
        try await repository.connectURL()
    }

    /// Nach erfolgreicher Anmeldung: Der erste Abgleich läuft auf dem Server; ein paar Mal nachsehen.
    func didConnect() async {
        for delay in [0, 2, 4, 6] {
            try? await Task.sleep(for: .seconds(delay))
            await reload()
            revision += 1
            if connections.contains(where: { $0.lastSyncAt != nil }) { break }
        }
    }

    func setSelected(_ calendar: ExternalCalendar, _ selected: Bool) async throws(FamiliarError) {
        try await repository.setSelected(calendarID: calendar.id, selected)
        await reload()
        revision += 1
        // Neu ausgewählte Kalender werden auf dem Server abgeglichen.
        if selected {
            try? await Task.sleep(for: .seconds(3))
            revision += 1
        }
    }

    func disconnect(_ connection: CalendarConnection) async throws(FamiliarError) {
        try await repository.disconnect(connectionID: connection.id)
        await reload()
        revision += 1
    }

    func syncNow() async throws(FamiliarError) -> Bool {
        let started = try await repository.requestSync()
        if started {
            try? await Task.sleep(for: .seconds(4))
            await reload()
            revision += 1
        }
        return started
    }

    func events(from: Date, to: Date) async -> [ExternalEvent] {
        guard isConnected || state != .loaded else { return [] }
        return (try? await repository.events(from: from, to: to)) ?? []
    }

    func stop() {
        connections = []
        state = .idle
    }
}
