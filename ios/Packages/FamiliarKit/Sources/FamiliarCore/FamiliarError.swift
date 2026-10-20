import Foundation

/// Fehler, die die App dem Nutzer zeigt. Datenquellen übersetzen ihre Fehler hierher.
public enum FamiliarError: Error, Hashable, Sendable {
    /// Fehler aus dem Fehlerkatalog der RPCs (`private.raise_app_error`) mit deutscher Server-Meldung.
    case app(key: AppErrorKey, message: String)
    case notAuthenticated
    case invalidEmailCode
    case emailRateLimited
    case offline
    case unknown(message: String)

    public var message: String {
        switch self {
        case .app(_, let message): message
        case .notAuthenticated: String(localized: "Du bist nicht mehr angemeldet. Bitte melde dich erneut an.")
        case .invalidEmailCode: String(localized: "Der Code ist falsch oder abgelaufen. Fordere bei Bedarf einen neuen an.")
        case .emailRateLimited: String(localized: "Zu viele E-Mails in kurzer Zeit. Bitte warte einen Moment und versuche es erneut.")
        case .offline: String(localized: "Keine Verbindung zum Server. Prüfe deine Internetverbindung.")
        case .unknown: String(localized: "Etwas ist schiefgelaufen. Bitte versuche es erneut.")
        }
    }
}

/// Stabile Fehlerschlüssel aus dem Feld `hint` der RPC-Fehler (Datenmodell, „Fehlerkatalog“).
/// Nur diese Werte werden ausgewertet; andere Hints (z. B. von Supabase bei Rechtefehlern) nicht.
public enum AppErrorKey: String, CaseIterable, Hashable, Sendable {
    case notAuthenticated = "not_authenticated"
    case invalidFamilyName = "invalid_family_name"
    case invalidColor = "invalid_color"
    case invalidDisplayName = "invalid_display_name"
    case invalidAvatarPath = "invalid_avatar_path"
    case invalidRole = "invalid_role"
    case familyNotFound = "family_not_found"
    case memberNotFound = "member_not_found"
    case inviteNotFound = "invite_not_found"
    case profileNotFound = "profile_not_found"
    case adminRequired = "admin_required"
    case permissionDeniedInvite = "permission_denied_invite"
    case permissionDeniedManageFamily = "permission_denied_manage_family"
    case permissionDeniedRemoveMembers = "permission_denied_remove_members"
    case adminRequiredToRemoveAdmin = "admin_required_to_remove_admin"
    case lastAdmin = "last_admin"
    case inviteCodeGenerationFailed = "invite_code_generation_failed"
}
