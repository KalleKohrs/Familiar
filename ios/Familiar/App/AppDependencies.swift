import FamiliarCore
import FamiliarData
import Foundation

/// Datenquellen der App. Normalerweise Supabase; in Debug-Builds mit dem Startargument
/// `-FamiliarInMemoryBackend` ein Backend ohne Netzwerk (UI-Tests, Previews).
struct AppDependencies {
    let auth: any AuthService
    let profiles: any ProfileRepository
    let families: any FamilyRepository

    static func live() -> AppDependencies {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-FamiliarInMemoryBackend") {
            return .inMemory(scenario: .fromLaunchArguments())
        }
        #endif
        guard let configuration = SupabaseConfiguration() else {
            fatalError("Supabase-Konfiguration fehlt in der Info.plist (siehe Config/Supabase.xcconfig).")
        }
        let backend = SupabaseBackend(configuration: configuration)
        return AppDependencies(auth: backend.auth, profiles: backend.profiles, families: backend.families)
    }
}
