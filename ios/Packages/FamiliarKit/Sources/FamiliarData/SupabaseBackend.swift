import FamiliarCore
import Foundation
import Supabase

/// Verbindungsdaten zum Supabase-Projekt. In der App nur URL und Publishable-Key (kein Geheimnis).
public struct SupabaseConfiguration: Sendable {
    public let url: URL
    public let publishableKey: String

    public init(url: URL, publishableKey: String) {
        self.url = url
        self.publishableKey = publishableKey
    }

    /// Liest `FamiliarSupabaseHost` und `FamiliarSupabasePublishableKey` aus der Info.plist
    /// (gesetzt über `Config/Supabase.xcconfig`). In xcconfig-Dateien beginnt `//` einen Kommentar,
    /// deshalb steht dort nur der Host und das Schema wird hier ergänzt.
    public init?(bundle: Bundle = .main) {
        guard
            let host = bundle.object(forInfoDictionaryKey: "FamiliarSupabaseHost") as? String, !host.isEmpty,
            let key = bundle.object(forInfoDictionaryKey: "FamiliarSupabasePublishableKey") as? String, !key.isEmpty,
            let url = URL(string: "https://\(host)")
        else { return nil }
        self.init(url: url, publishableKey: key)
    }
}

/// Alle Datenquellen auf Basis eines gemeinsamen `SupabaseClient`.
public struct SupabaseBackend: Sendable {
    public let auth: any AuthService
    public let profiles: any ProfileRepository
    public let families: any FamilyRepository

    public init(configuration: SupabaseConfiguration) {
        let client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey,
            options: SupabaseClientOptions(
                // Sitzung liegt standardmäßig im Schlüsselbund (KeychainLocalStorage) und wird
                // automatisch erneuert. Neues Verhalten: gespeicherte Sitzung sofort melden,
                // ein Ablauf wird danach per Refresh bzw. `signedOut` aufgelöst.
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
        auth = SupabaseAuthService(client: client)
        profiles = SupabaseProfileRepository(client: client)
        families = SupabaseFamilyRepository(client: client)
    }
}

/// Führt einen Supabase-Aufruf aus und übersetzt Fehler in ``FamiliarError``.
func perform<T>(_ operation: () async throws -> T) async throws(FamiliarError) -> T {
    do {
        return try await operation()
    } catch {
        throw FamiliarError(supabaseError: error)
    }
}

extension SupabaseClient {
    func currentUserID() async throws(FamiliarError) -> UUID {
        try await perform { try await auth.session.user.id }
    }
}
