#if DEBUG
import FamiliarCore
import FamiliarDesign
import Foundation
import SwiftUI

/// Backend ohne Netzwerk für UI-Tests und Previews (nur Debug-Builds).
///
/// Start mit `-FamiliarInMemoryBackend`; `-FamiliarInMemoryScenario ready` beginnt angemeldet
/// mit einer Familie. Gültiger E-Mail-Code: ``validEmailCode``; Beitritt mit ``joinableCode``.
/// Die Regeln sind bewusst einfach gehalten – maßgeblich bleiben Server und SQL-Tests.
actor InMemoryBackend {
    enum Scenario: String {
        case signedOut
        case ready

        static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Scenario {
            guard let index = arguments.firstIndex(of: "-FamiliarInMemoryScenario"),
                  arguments.indices.contains(index + 1) else { return .signedOut }
            return Scenario(rawValue: arguments[index + 1]) ?? .signedOut
        }
    }

    static let validEmailCode = "123456"
    static let joinableCode = "TEST2345"

    private var user: (id: UUID, email: String)?
    private var profiles: [UUID: Profile] = [:]
    private var families: [UUID: Family] = [:]
    private var members: [UUID: [FamilyMember]] = [:]
    private var invites: [String: FamilyInvite] = [:]
    private var avatarFiles: [String: URL] = [:]
    private var listeners: [UUID: AsyncStream<AuthState>.Continuation] = [:]

    init(scenario: Scenario) {
        let anna = UUID()
        profiles[anna] = Profile(id: anna, displayName: "Anna")
        let example = Family(id: UUID(), name: "Familie Beispiel", colorHex: "#8FD19E", createdBy: anna)
        families[example.id] = example
        members[example.id] = [FamilyMember(familyID: example.id, userID: anna, role: .admin, profile: profiles[anna])]
        invites[Self.joinableCode] = FamilyInvite(id: UUID(), familyID: example.id, code: Self.joinableCode,
                                                  expiresAt: .now.addingTimeInterval(7 * 24 * 3600))

        if scenario == .ready {
            let me = UUID()
            user = (me, "kalle@example.test")
            profiles[me] = Profile(id: me, displayName: "Kalle")
            let family = Family(id: UUID(), name: "Familie Kohrs", colorHex: "#FF7F66", createdBy: me)
            families[family.id] = family
            members[family.id] = [
                FamilyMember(familyID: family.id, userID: me, role: .admin, profile: profiles[me]),
                FamilyMember(familyID: family.id, userID: anna, role: .member, profile: profiles[anna]),
            ]
        }
    }

    private var state: AuthState {
        user.map { .signedIn(userID: $0.id, email: $0.email) } ?? .signedOut
    }

    private func register(_ continuation: AsyncStream<AuthState>.Continuation) {
        let id = UUID()
        listeners[id] = continuation
        continuation.yield(state)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unregister(id) }
        }
    }

    private func unregister(_ id: UUID) {
        listeners[id] = nil
    }

    private func publish() {
        for listener in listeners.values { listener.yield(state) }
    }

    private func requireUser() throws(FamiliarError) -> UUID {
        guard let user else { throw .notAuthenticated }
        return user.id
    }

    private func membership(_ familyID: UUID, for userID: UUID) -> FamilyMembership? {
        guard let family = families[familyID], let familyMembers = members[familyID],
              familyMembers.contains(where: { $0.userID == userID }) else { return nil }
        let current = familyMembers.map { member in
            var member = member
            member.profile = profiles[member.userID]
            return member
        }
        return FamilyMembership(family: family, members: current, currentUserID: userID)
    }
}

extension InMemoryBackend: AuthService {
    nonisolated func authStates() -> AsyncStream<AuthState> {
        AsyncStream { continuation in
            Task { await self.register(continuation) }
        }
    }

    func sendEmailCode(to email: String) async throws(FamiliarError) {}

    func verifyEmailCode(_ code: String, email: String) async throws(FamiliarError) {
        guard InputRules.trimmed(code) == Self.validEmailCode else { throw .invalidEmailCode }
        let address = InputRules.trimmed(email).lowercased()
        let id = UUID()
        let localPart = address.split(separator: "@").first.map(String.init) ?? "Mitglied"
        profiles[id] = Profile(id: id, displayName: localPart)
        user = (id, address)
        publish()
    }

    func signOut(everywhere: Bool) async throws(FamiliarError) {
        user = nil
        publish()
    }
}

extension InMemoryBackend: ProfileRepository {
    func myProfile() async throws(FamiliarError) -> Profile {
        let id = try requireUser()
        guard let profile = profiles[id] else { throw .app(key: .profileNotFound, message: "Profil nicht gefunden.") }
        return profile
    }

    func updateDisplayName(_ name: String) async throws(FamiliarError) -> Profile {
        let id = try requireUser()
        guard InputRules.isValidDisplayName(name) else {
            throw .app(key: .invalidDisplayName, message: "Der Anzeigename muss 1 bis 80 Zeichen lang sein.")
        }
        profiles[id]?.displayName = InputRules.trimmed(name)
        profiles[id]?.updatedAt = .now
        return try await myProfile()
    }

    func uploadAvatar(jpegData: Data) async throws(FamiliarError) -> Profile {
        let id = try requireUser()
        let path = Profile.avatarStoragePath(for: id)
        let file = URL.temporaryDirectory.appending(path: "familiar-avatar-\(id.uuidString).jpg")
        do { try jpegData.write(to: file) } catch { throw .unknown(message: error.localizedDescription) }
        avatarFiles[path] = file
        profiles[id]?.avatarPath = path
        profiles[id]?.updatedAt = .now
        return try await myProfile()
    }

    func removeAvatar() async throws(FamiliarError) -> Profile {
        let id = try requireUser()
        profiles[id]?.avatarPath = nil
        profiles[id]?.updatedAt = .now
        return try await myProfile()
    }

    func avatarURL(path: String) async throws(FamiliarError) -> URL {
        guard let url = avatarFiles[path] else { throw .unknown(message: "Bild nicht gefunden.") }
        return url
    }
}

extension InMemoryBackend: FamilyRepository {
    func myFamilies() async throws(FamiliarError) -> [FamilyMembership] {
        let id = try requireUser()
        return families.keys
            .compactMap { membership($0, for: id) }
            .sorted { $0.family.name.localizedStandardCompare($1.family.name) == .orderedAscending }
    }

    func createFamily(name: String, colorHex: String) async throws(FamiliarError) -> Family {
        let id = try requireUser()
        guard InputRules.isValidFamilyName(name) else {
            throw .app(key: .invalidFamilyName, message: "Der Familienname muss 1 bis 60 Zeichen lang sein.")
        }
        let family = Family(id: UUID(), name: InputRules.trimmed(name), colorHex: colorHex.uppercased(), createdBy: id)
        families[family.id] = family
        members[family.id] = [FamilyMember(familyID: family.id, userID: id, role: .admin)]
        return family
    }

    func joinFamily(code: String) async throws(FamiliarError) -> JoinFamilyResult {
        let id = try requireUser()
        let normalized = InviteCode.normalize(code)
        guard InviteCode.isValid(normalized) else {
            return JoinFamilyResult(status: .invalidFormat, message: "Ein Einladungscode hat 8 Zeichen (Buchstaben und Ziffern).")
        }
        guard let invite = invites[normalized] else {
            return JoinFamilyResult(status: .invalidCode, message: "Dieser Einladungscode ist ungültig.")
        }
        if members[invite.familyID]?.contains(where: { $0.userID == id }) == true {
            return JoinFamilyResult(status: .alreadyMember, familyID: invite.familyID, message: "Du bist bereits Mitglied dieser Familie.")
        }
        members[invite.familyID, default: []].append(FamilyMember(familyID: invite.familyID, userID: id, role: .member))
        return JoinFamilyResult(status: .joined, familyID: invite.familyID, message: "Du bist der Familie beigetreten.")
    }

    func createInvite(familyID: UUID) async throws(FamiliarError) -> FamilyInvite {
        let id = try requireUser()
        guard let membership = membership(familyID, for: id) else {
            throw .app(key: .familyNotFound, message: "Familie nicht gefunden oder du bist kein Mitglied.")
        }
        guard membership.allows(.invite) else {
            throw .app(key: .permissionDeniedInvite, message: "Du darfst in dieser Familie niemanden einladen.")
        }
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        let code = String((0..<InviteCode.length).map { _ in alphabet.randomElement()! })
        let invite = FamilyInvite(id: UUID(), familyID: familyID, code: code, expiresAt: .now.addingTimeInterval(7 * 24 * 3600))
        invites[code] = invite
        return invite
    }

    func leaveFamily(familyID: UUID) async throws(FamiliarError) -> LeaveFamilyResult {
        let id = try requireUser()
        guard let membership = membership(familyID, for: id) else {
            throw .app(key: .familyNotFound, message: "Familie nicht gefunden oder du bist kein Mitglied.")
        }
        if membership.members.count == 1 {
            families[familyID] = nil
            members[familyID] = nil
            return .familyDeleted
        }
        guard !membership.isLastAdminWithOthers else {
            throw .app(key: .lastAdmin, message: "Die Familie braucht mindestens einen Admin. Ernenne zuerst eine andere Person zum Admin.")
        }
        members[familyID]?.removeAll { $0.userID == id }
        return .left
    }
}

extension AppDependencies {
    static func inMemory(scenario: InMemoryBackend.Scenario) -> AppDependencies {
        let backend = InMemoryBackend(scenario: scenario)
        return AppDependencies(auth: backend, profiles: backend, families: backend)
    }
}

extension View {
    /// Umgebung für Xcode-Previews mit dem In-Memory-Backend.
    func previewEnvironment(_ scenario: InMemoryBackend.Scenario) -> some View {
        let dependencies = AppDependencies.inMemory(scenario: scenario)
        let session = SessionStore(dependencies: dependencies, defaults: UserDefaults(suiteName: "preview") ?? .standard)
        return self
            .environment(session)
            .environment(AvatarImageStore(profiles: dependencies.profiles))
            .preferredColorScheme(.dark)
            .tint(FamiliarColor.accent)
            .task { session.start() }
    }
}
#endif
