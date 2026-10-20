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

public protocol FamilyRepository: Sendable {
    func myFamilies() async throws(FamiliarError) -> [FamilyMembership]
    func createFamily(name: String, colorHex: String) async throws(FamiliarError) -> Family
    func joinFamily(code: String) async throws(FamiliarError) -> JoinFamilyResult
    func createInvite(familyID: UUID) async throws(FamiliarError) -> FamilyInvite
    func leaveFamily(familyID: UUID) async throws(FamiliarError) -> LeaveFamilyResult
}
