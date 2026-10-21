import Foundation

/// Anmeldestatus, wie ihn die App braucht.
public enum AuthState: Hashable, Sendable {
    case signedOut
    case signedIn(userID: UUID, email: String?)
}

/// Anmeldung per E-Mail-Code. Implementierungen: Supabase (FamiliarData) und In-Memory (Tests).
public protocol AuthService: Sendable {
    /// Liefert zuerst den gespeicherten Zustand und danach jede Änderung.
    func authStates() -> AsyncStream<AuthState>
    func sendEmailCode(to email: String) async throws(FamiliarError)
    func verifyEmailCode(_ code: String, email: String) async throws(FamiliarError)
    /// `everywhere = false`: nur dieses Gerät; `true`: alle Sitzungen des Kontos.
    func signOut(everywhere: Bool) async throws(FamiliarError)
    /// Konto endgültig löschen (Edge Function `account-delete`); danach abgemeldet.
    func deleteAccount() async throws(FamiliarError)
}

public protocol ProfileRepository: Sendable {
    func myProfile() async throws(FamiliarError) -> Profile
    func updateDisplayName(_ name: String) async throws(FamiliarError) -> Profile
    /// Lädt ein bereits verkleinertes JPEG hoch und trägt es im Profil ein.
    func uploadAvatar(jpegData: Data) async throws(FamiliarError) -> Profile
    func removeAvatar() async throws(FamiliarError) -> Profile
    /// Kurzlebige URL zum Anzeigen eines Profilbilds.
    func avatarURL(path: String) async throws(FamiliarError) -> URL
}

public protocol TaskRepository: Sendable {
    /// Offene, nicht gelöschte Aufgaben aller Familien, die der Nutzer sehen darf (RLS).
    func openTasks() async throws(FamiliarError) -> [TaskItem]
    func task(id: UUID) async throws(FamiliarError) -> TaskItem
    /// Erledigte und gelöschte Aufgaben der letzten 30 Tage (Verlauf), nur sichtbare (RLS).
    func historyTasks() async throws(FamiliarError) -> [TaskItem]
    /// Lädt Bild und Miniatur nach `task-images/{family_id}/{id}.jpg` bzw. `…_thumb.jpg`.
    func upload(_ image: PreparedImage, familyID: UUID) async throws(FamiliarError)
    func createTask(_ input: TaskInput) async throws(FamiliarError) -> TaskItem
    func updateTask(id: UUID, expectedVersion: Int, _ input: TaskInput) async throws(FamiliarError) -> TaskItem
    func complete(taskID: UUID, scope: CompletionScope) async throws(FamiliarError)
    func uncomplete(taskID: UUID, scope: CompletionScope) async throws(FamiliarError)
    func delete(taskID: UUID) async throws(FamiliarError)
    func restore(taskID: UUID) async throws(FamiliarError)
    /// Neue Serie (`input.recurrence` gesetzt); erzeugt sofort die ersten Vorkommen.
    func createSeries(_ input: TaskInput) async throws(FamiliarError)
    /// „Dieses und zukünftige“ ab dem Vorkommen `taskID` (`input.recurrence` gesetzt).
    func updateSeries(fromTaskID taskID: UUID, expectedVersion: Int, _ input: TaskInput) async throws(FamiliarError) -> TaskItem
    /// „Gesamte Serie“ löschen; liefert die ID des Verlaufseintrags (für Rückgängig).
    func deleteSeries(fromTaskID taskID: UUID) async throws(FamiliarError) -> UUID
    func restoreSeries(deletionID: UUID) async throws(FamiliarError)
    /// Serien-Löschungen der letzten 30 Tage, die noch nicht wiederhergestellt sind.
    func seriesDeletions() async throws(FamiliarError) -> [SeriesDeletion]
    /// Nicht gelöschte Aufgaben (offen und erledigt) mit Startdatum im Zeitraum, für den Kalender.
    func calendarTasks(from: LocalDate, through: LocalDate) async throws(FamiliarError) -> [TaskItem]
    /// Künftige, noch nicht erzeugte Vorkommen sichtbarer Serien (höchstens 400 Tage).
    func projectedOccurrences(from: LocalDate, through: LocalDate) async throws(FamiliarError) -> [ProjectedOccurrence]
    /// Kurzlebige URL für ein Aufgabenbild oder eine Miniatur.
    func imageURL(path: String) async throws(FamiliarError) -> URL
    /// Hinweise „Aufgabe geändert“ (Realtime); der Inhalt wird danach neu geladen.
    func changes(for userID: UUID) -> AsyncStream<UUID>
}

public protocol FamilyRepository: Sendable {
    func myFamilies() async throws(FamiliarError) -> [FamilyMembership]
    func createFamily(name: String, colorHex: String) async throws(FamiliarError) -> Family
    func joinFamily(code: String) async throws(FamiliarError) -> JoinFamilyResult
    func createInvite(familyID: UUID) async throws(FamiliarError) -> FamilyInvite
    func leaveFamily(familyID: UUID) async throws(FamiliarError) -> LeaveFamilyResult
    /// Name, Farbe, Sichtbarkeit (Recht „Familie bearbeiten“).
    func updateFamily(familyID: UUID, name: String, colorHex: String, visibility: TaskVisibility) async throws(FamiliarError)
    /// Schalter für Mitglieder setzen (nur Admin); nur die übergebenen Rechte ändern sich.
    func setPermissions(familyID: UUID, _ changes: [FamilyPermission: Bool]) async throws(FamiliarError)
    func setMemberRole(familyID: UUID, userID: UUID, role: FamilyRole) async throws(FamiliarError)
    func removeMember(familyID: UUID, userID: UUID) async throws(FamiliarError)
    /// Familie samt Aufgaben löschen (nur Admin).
    func deleteFamily(familyID: UUID) async throws(FamiliarError)
}

/// Persönliche Termine aus externen Kalendern (Plan, Abschnitt 7) – anbieterunabhängig.
/// Bis Outlook angebunden ist (Phase 8), liefert ``NoExternalEvents`` nichts.
public protocol ExternalEventRepository: Sendable {
    func events(from: Date, to: Date) async throws(FamiliarError) -> [ExternalEvent]
}

public struct NoExternalEvents: ExternalEventRepository {
    public init() {}

    public func events(from: Date, to: Date) async throws(FamiliarError) -> [ExternalEvent] { [] }
}
