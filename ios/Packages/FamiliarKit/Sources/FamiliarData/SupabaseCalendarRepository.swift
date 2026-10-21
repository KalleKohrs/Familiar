import FamiliarCore
import Foundation
import Supabase

/// Persönliche Outlook-Kalender (Migration 0011). RLS liefert nur eigene Daten; Tokens bleiben auf dem Server.
final class SupabaseCalendarRepository: ExternalCalendarRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func connections() async throws(FamiliarError) -> [CalendarConnection] {
        try await perform {
            try await client.from("calendar_connections")
                .select("*, external_calendars(id, name, color, is_default, is_selected)")
                .order("created_at")
                .execute()
                .value
        }
    }

    func connectLinks() async throws(FamiliarError) -> CalendarConnectLinks {
        let response: ConnectResponse = try await perform {
            try await client.functions.invoke("outlook-oauth-start", options: FunctionInvokeOptions(method: .post))
        }
        guard let url = URL(string: response.url) else {
            throw .unknown(message: "Ungültige Anmelde-Adresse")
        }
        return CalendarConnectLinks(connect: url, adminConsent: response.consentURL.flatMap(URL.init(string:)))
    }

    func setSelected(calendarID: UUID, _ selected: Bool) async throws(FamiliarError) {
        _ = try await perform {
            try await client.rpc("set_calendar_selected", params: SelectParams(calendarID: calendarID, selected: selected)).execute()
        }
    }

    func disconnect(connectionID: UUID) async throws(FamiliarError) {
        _ = try await perform {
            try await client.rpc("disconnect_calendar", params: ["p_connection_id": connectionID.uuidString]).execute()
        }
    }

    func requestSync() async throws(FamiliarError) -> Bool {
        try await perform {
            try await client.rpc("request_calendar_sync").execute().value
        }
    }

    func events(from: Date, to: Date) async throws(FamiliarError) -> [ExternalEvent] {
        try await perform {
            try await client.from("external_events")
                .select("id, calendar_id, provider, title, starts_at, ends_at, is_all_day, start_date, end_date, location_name, organizer_name, is_cancelled")
                .lt("starts_at", value: to.formatted(.iso8601))
                .gt("ends_at", value: from.formatted(.iso8601))
                .eq("is_cancelled", value: false)
                .order("starts_at")
                .execute()
                .value
        }
    }
}

private struct ConnectResponse: Decodable {
    let url: String
    let consentURL: String?

    enum CodingKeys: String, CodingKey {
        case url
        case consentURL = "consent_url"
    }
}

private struct SelectParams: Encodable {
    let calendarID: UUID
    let selected: Bool

    enum CodingKeys: String, CodingKey {
        case calendarID = "p_calendar_id"
        case selected = "p_selected"
    }
}
