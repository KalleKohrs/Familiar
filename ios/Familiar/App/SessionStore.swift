import FamiliarCore
import Foundation
import Observation

/// Zustand nach der Anmeldung: Profil, Familien und Onboarding-Schritt.
///
/// Die Datenbank ist maßgeblich: Nach jeder Änderung werden Profil bzw. Familien neu geladen,
/// statt lokale Kopien fortzuschreiben.
@Observable
final class SessionStore {
    enum Phase: Equatable {
        case launching
        case signedOut
        case onboarding(OnboardingStep)
        case ready
        case failed(FamiliarError)
    }

    private(set) var phase: Phase = .launching
    private(set) var email: String?
    private(set) var profile: Profile?
    private(set) var families: [FamilyMembership] = []

    let dependencies: AppDependencies
    private let defaults: UserDefaults
    private(set) var userID: UUID?
    private var authTask: Task<Void, Never>?

    init(dependencies: AppDependencies, defaults: UserDefaults = .standard) {
        self.dependencies = dependencies
        self.defaults = defaults
    }

    /// Beobachtet den Anmeldestatus; der erste Wert ist die gespeicherte Sitzung.
    func start() {
        guard authTask == nil else { return }
        restorePendingInvite()
        let states = dependencies.auth.authStates()
        authTask = Task { [weak self] in
            for await state in states {
                await self?.handle(state)
            }
        }
    }

    /// Jede Änderung des Anmeldestatus (Konto bzw. `nil` nach dem Abmelden) – auch ohne Zutun der
    /// Person, etwa wenn die Sitzung auf einem anderen Gerät beendet wurde.
    var onAccountChange: ((UUID?) -> Void)?

    private func handle(_ state: AuthState) async {
        switch state {
        case .signedOut:
            userID = nil
            email = nil
            profile = nil
            families = []
            phase = .signedOut
            onAccountChange?(nil)
        case .signedIn(let id, let email):
            userID = id
            self.email = email
            onAccountChange?(id)
            await reload()
        }
    }

    /// Lädt Profil und Familien und bestimmt den nächsten Schritt.
    func reload() async {
        let requestedFor = userID
        do throws(FamiliarError) {
            // Beide Anfragen gleichzeitig: Sie hängen nicht voneinander ab, nacheinander kostete das einen
            // zusätzlichen Netz-Rundlauf vor dem ersten Bild.
            async let profileRequest = captured { () async throws(FamiliarError) -> Profile in try await dependencies.profiles.myProfile() }
            async let familiesRequest = captured { () async throws(FamiliarError) -> [FamilyMembership] in try await dependencies.families.myFamilies() }
            let (profileResult, familiesResult) = await (profileRequest, familiesRequest)
            let loadedProfile = try profileResult.get()
            let loadedFamilies = try familiesResult.get()
            // Während des Ladens abgemeldet oder Konto gewechselt: alten Stand nicht übernehmen.
            guard userID == requestedFor, userID != nil else { return }
            profile = loadedProfile
            families = loadedFamilies
            updatePhase()
        } catch {
            guard userID == requestedFor else { return }
            phase = error == .notAuthenticated ? .signedOut : .failed(error)
        }
    }

    // MARK: Einladungslinks

    private static let pendingInviteKey = "invite.pendingCode"

    /// Code aus einem geöffneten Einladungslink. Bleibt über Anmeldung und Neustart vorgemerkt,
    /// bis die Person beitritt oder ablehnt (Plan Abschnitt 6).
    private(set) var pendingInviteCode: String?

    /// `true`, wenn der Link ein Einladungslink war.
    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard let code = InviteLink.code(from: url) else { return false }
        pendingInviteCode = code
        defaults.set(code, forKey: Self.pendingInviteKey)
        return true
    }

    func clearPendingInvite() {
        pendingInviteCode = nil
        defaults.removeObject(forKey: Self.pendingInviteKey)
    }

    /// Nach dem Start: vorgemerkten Code aus einer früheren Sitzung übernehmen.
    private func restorePendingInvite() {
        if pendingInviteCode == nil { pendingInviteCode = defaults.string(forKey: Self.pendingInviteKey) }
    }

    // MARK: Onboarding

    private var profileConfirmedKey: String? {
        userID.map { "onboarding.profileConfirmed.\($0.uuidString)" }
    }

    private var profileConfirmed: Bool {
        profileConfirmedKey.map { defaults.bool(forKey: $0) } ?? false
    }

    /// Name und Bild wurden im Onboarding bestätigt.
    func confirmProfile() {
        if let profileConfirmedKey { defaults.set(true, forKey: profileConfirmedKey) }
        updatePhase()
    }

    private func updatePhase() {
        switch OnboardingFlow.nextStep(hasFamily: !families.isEmpty, profileConfirmed: profileConfirmed) {
        case .done:
            // Wer einmal drin war, muss das Profil nach dem Verlassen der letzten Familie nicht erneut bestätigen.
            if let profileConfirmedKey { defaults.set(true, forKey: profileConfirmedKey) }
            phase = .ready
        case let step:
            phase = .onboarding(step)
        }
    }

    // MARK: Profil

    func saveDisplayName(_ name: String) async throws(FamiliarError) {
        profile = try await dependencies.profiles.updateDisplayName(name)
        try await refreshFamilies()
    }

    func uploadAvatar(jpegData: Data) async throws(FamiliarError) {
        profile = try await dependencies.profiles.uploadAvatar(jpegData: jpegData)
        try await refreshFamilies()
    }

    func removeAvatar() async throws(FamiliarError) {
        profile = try await dependencies.profiles.removeAvatar()
        try await refreshFamilies()
    }

    // MARK: Familien

    /// Titel oben links: Name der einzigen Familie oder „Alle Familien“.
    var familyHeaderTitle: String {
        switch families.count {
        case 0: String(localized: "Familie")
        case 1: families[0].family.name
        default: String(localized: "Alle Familien")
        }
    }

    func membership(_ familyID: UUID) -> FamilyMembership? {
        families.first { $0.id == familyID }
    }

    /// Mitglied einer Familie (für Namen und Profilbilder von zugewiesenen Personen).
    func member(_ userID: UUID, in familyID: UUID) -> FamilyMember? {
        membership(familyID)?.members.first { $0.userID == userID }
    }

    /// Anzeigename; wer die Familie verlassen hat, erscheint neutral.
    func displayName(of userID: UUID, in familyID: UUID) -> String {
        if userID == self.userID, let profile { return profile.displayName }
        return member(userID, in: familyID)?.displayName ?? String(localized: "Ehemaliges Mitglied")
    }

    /// Anzeigefarben: ähnliche Familienfarben werden lokal leicht verschoben (Plan, Abschnitt 4).
    var familyDisplayColors: [UUID: RGBColor] {
        let inputs = families.map { FamilyColorInput(familyID: $0.id.uuidString, color: $0.family.color) }
        let resolved = FamilyColorResolver.displayColors(for: inputs)
        return Dictionary(uniqueKeysWithValues: families.map { ($0.id, resolved[$0.id.uuidString] ?? $0.family.color) })
    }

    func refreshFamilies() async throws(FamiliarError) {
        let requestedFor = userID
        let loaded = try await dependencies.families.myFamilies()
        guard userID == requestedFor else { return }
        families = loaded
        if case .launching = phase { return }
        if phase != .signedOut { updatePhase() }
    }

    func createFamily(name: String, colorHex: String) async throws(FamiliarError) {
        _ = try await dependencies.families.createFamily(name: name, colorHex: colorHex)
        try await refreshFamilies()
    }

    /// Ungültige Codes sind kein Fehler, sondern ein Ergebnis mit Meldung (Rate-Limit).
    func joinFamily(code: String) async throws(FamiliarError) -> JoinFamilyResult {
        let result = try await dependencies.families.joinFamily(code: code)
        if result.isSuccess { try await refreshFamilies() }
        return result
    }

    func createInvite(familyID: UUID) async throws(FamiliarError) -> FamilyInvite {
        try await dependencies.families.createInvite(familyID: familyID)
    }

    func leaveFamily(_ familyID: UUID) async throws(FamiliarError) {
        _ = try await dependencies.families.leaveFamily(familyID: familyID)
        try await refreshFamilies()
    }

    // MARK: Familie verwalten (Phase 9)

    func updateFamily(_ familyID: UUID, name: String, colorHex: String, visibility: TaskVisibility) async throws(FamiliarError) {
        try await dependencies.families.updateFamily(familyID: familyID, name: name, colorHex: colorHex, visibility: visibility)
        try await refreshFamilies()
    }

    func setPermission(_ permission: FamilyPermission, allowed: Bool, in familyID: UUID) async throws(FamiliarError) {
        try await dependencies.families.setPermissions(familyID: familyID, [permission: allowed])
        try await refreshFamilies()
    }

    func setRole(_ role: FamilyRole, for userID: UUID, in familyID: UUID) async throws(FamiliarError) {
        try await dependencies.families.setMemberRole(familyID: familyID, userID: userID, role: role)
        try await refreshFamilies()
    }

    func removeMember(_ userID: UUID, from familyID: UUID) async throws(FamiliarError) {
        try await dependencies.families.removeMember(familyID: familyID, userID: userID)
        try await refreshFamilies()
    }

    func deleteFamily(_ familyID: UUID) async throws(FamiliarError) {
        try await dependencies.families.deleteFamily(familyID: familyID)
        try await refreshFamilies()
    }

    /// Mindestens eine Familie, in der der Nutzer Aufgaben anlegen darf.
    var canCreateTasksAnywhere: Bool { families.contains { $0.allows(.createTasks) } }

    func allows(_ permission: FamilyPermission, in familyID: UUID) -> Bool {
        membership(familyID)?.allows(permission) ?? false
    }

    // MARK: Abmelden

    /// Der Anmeldestatus meldet danach `signedOut`; Gerätetokens werden ab Phase 7 vorher entfernt.
    /// Name aus „Mit Apple anmelden“ (nur bei der ersten Anmeldung) als Vorschlag für den Profil-Schritt.
    private(set) var suggestedDisplayName: String?

    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws(FamiliarError) {
        suggestedDisplayName = fullName
        try await dependencies.auth.signInWithApple(idToken: idToken, nonce: nonce, fullName: fullName)
    }

    func signInWithGoogle(idToken: String, accessToken: String, nonce: String) async throws(FamiliarError) {
        try await dependencies.auth.signInWithGoogle(idToken: idToken, accessToken: accessToken, nonce: nonce)
    }

    /// Ob vor dem Löschen eine Bestätigung mit Apple nötig ist (Widerruf der Apple-Anmeldung).
    func needsAppleConfirmationForDeletion() async -> Bool {
        await dependencies.auth.isLinkedToApple()
    }

    /// Läuft vor dem Abmelden (Gerät für Mitteilungen abmelden, solange die Sitzung noch gilt).
    var beforeSignOut: (() async -> Void)?

    func signOut(everywhere: Bool) async throws(FamiliarError) {
        await beforeSignOut?()
        do {
            try await dependencies.auth.signOut(everywhere: everywhere)
        } catch {
            // Abmelden fehlgeschlagen: weiter angemeldet (z. B. Widgets wieder zulassen).
            onAccountChange?(userID)
            throw error
        }
    }

    /// Konto endgültig löschen; danach meldet der Anmeldestatus `signedOut`.
    /// Vor dem Löschen des Kontos zusätzlich: Verbindung zu Google widerrufen (App setzt den Handler).
    var beforeAccountDeletion: (() async -> Void)?

    func deleteAccount(appleAuthorizationCode: String?) async throws(FamiliarError) {
        await beforeAccountDeletion?()
        await beforeSignOut?()
        do {
            try await dependencies.auth.deleteAccount(appleAuthorizationCode: appleAuthorizationCode)
        } catch {
            onAccountChange?(userID)
            throw error
        }
    }
}
