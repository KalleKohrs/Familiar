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
    // Aufgaben (Migration 0007)
    case invalidTaskTitle = "invalid_task_title"
    case invalidTaskDescription = "invalid_task_description"
    case invalidStart = "invalid_start"
    case invalidTimezone = "invalid_timezone"
    case invalidCompletionMode = "invalid_completion_mode"
    case assigneesRequired = "assignees_required"
    case assigneeNotMember = "assignee_not_member"
    case tooManyImages = "too_many_images"
    case invalidImage = "invalid_image"
    case taskNotFound = "task_not_found"
    case taskConflict = "task_conflict"
    case taskClosed = "task_closed"
    case completionModeLocked = "completion_mode_locked"
    case notAllowedToComplete = "not_allowed_to_complete"
    case invalidScope = "invalid_scope"
    // Wiederholungen (Migration 0009)
    case invalidRecurrence = "invalid_recurrence"
    case recurrenceRequiresDate = "recurrence_requires_date"
    case notAnOccurrence = "not_an_occurrence"
    case seriesNotFound = "series_not_found"
    case seriesDeleted = "series_deleted"
    case restoreSeriesInstead = "restore_series_instead"
    case seriesDeletionNotFound = "series_deletion_not_found"
    case invalidRange = "invalid_range"
    // Familienrechte (Migration 0010)
    case permissionDeniedCreateTasks = "permission_denied_create_tasks"
    case permissionDeniedEditTasks = "permission_denied_edit_tasks"
    case permissionDeniedDeleteTasks = "permission_denied_delete_tasks"
    // Kalender (Migration 0011)
    case calendarNotFound = "calendar_not_found"
    // Reihum und Anstupsen (Migration 0018)
    case invalidRotation = "invalid_rotation"
    case rotationNeedsTwo = "rotation_needs_two"
    case nudgeSelf = "nudge_self"
    case nudgeNotOpen = "nudge_not_open"
    case nudgeTooSoon = "nudge_too_soon"
}
