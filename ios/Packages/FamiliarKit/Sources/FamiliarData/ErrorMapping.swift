import FamiliarCore
import Foundation
import Supabase

extension FamiliarError {
    /// Übersetzt Fehler aus dem Supabase-SDK.
    ///
    /// RPC-Fehler tragen den stabilen Schlüssel im Feld `hint`. Ausgewertet werden nur Schlüssel aus
    /// dem Fehlerkatalog, weil Supabase an Rechtefehler einen eigenen englischen Hint hängt.
    init(supabaseError error: any Error) {
        switch error {
        case let error as FamiliarError:
            self = error
        case let error as PostgrestError:
            if let hint = error.hint, let key = AppErrorKey(rawValue: hint) {
                self = key == .notAuthenticated ? .notAuthenticated : .app(key: key, message: error.message)
            } else if error.code == "PGRST301" || error.code == "PGRST303" {
                // Ungültiges bzw. abgelaufenes JWT.
                self = .notAuthenticated
            } else {
                self = .unknown(message: error.message)
            }
        case let error as AuthError:
            self = FamiliarError(authError: error)
        case let error as URLError where Self.offlineCodes.contains(error.code):
            self = .offline
        default:
            self = .unknown(message: String(describing: error))
        }
    }

    private init(authError error: AuthError) {
        switch error {
        case .sessionMissing:
            self = .notAuthenticated
        case .api(let message, let code, _, _):
            switch code {
            case .otpExpired: self = .invalidEmailCode
            case .overEmailSendRateLimit, .overRequestRateLimit: self = .emailRateLimited
            default: self = .unknown(message: message)
            }
        default:
            self = .unknown(message: error.localizedDescription)
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut,
        .cannotFindHost, .cannotConnectToHost, .dataNotAllowed,
    ]
}
