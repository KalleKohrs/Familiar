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
    private var tasks: [UUID: TaskItem] = [:]
    private var imageFiles: [String: URL] = [:]

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
            let trash = TaskItem(id: UUID(), familyID: family.id, createdBy: anna, title: "Müll rausbringen",
                                 completionMode: .anyOne, createdAt: .now.addingTimeInterval(-60),
                                 assignees: [TaskAssignee(userID: me)])
            let room = TaskItem(id: UUID(), familyID: family.id, createdBy: anna, title: "Zimmer aufräumen",
                                description: "Jede Person ihr eigenes Zimmer.", completionMode: .each,
                                assignees: [TaskAssignee(userID: me), TaskAssignee(userID: anna)])
            tasks[trash.id] = trash
            tasks[room.id] = room
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


extension InMemoryBackend: TaskRepository {
    private func visibleTask(_ id: UUID) throws(FamiliarError) -> TaskItem {
        let me = try requireUser()
        guard let task = tasks[id], membership(task.familyID, for: me) != nil else {
            throw .app(key: .taskNotFound, message: "Aufgabe nicht gefunden oder für dich nicht sichtbar.")
        }
        return task
    }

    func openTasks() async throws(FamiliarError) -> [TaskItem] {
        let me = try requireUser()
        return tasks.values.filter { $0.isOpen && membership($0.familyID, for: me) != nil }
    }

    func task(id: UUID) async throws(FamiliarError) -> TaskItem {
        try visibleTask(id)
    }

    func historyTasks() async throws(FamiliarError) -> [TaskItem] {
        let me = try requireUser()
        return HistoryRules.entries(tasks.values.filter { !$0.isOpen && membership($0.familyID, for: me) != nil })
    }

    func upload(_ image: PreparedImage, familyID: UUID) async throws(FamiliarError) {
        let base = "\(familyID.uuidString.lowercased())/\(image.id.uuidString.lowercased())"
        for (suffix, data) in [(".jpg", image.jpegData), ("_thumb.jpg", image.thumbnailData)] {
            let file = URL.temporaryDirectory.appending(path: "familiar-\(image.id.uuidString)\(suffix)")
            do { try data.write(to: file) } catch { throw .unknown(message: error.localizedDescription) }
            imageFiles[base + suffix] = file
        }
    }

    private func images(for input: TaskInput) -> [TaskImage] {
        input.images.map { reference in
            let base = "\(input.familyID.uuidString.lowercased())/\(reference.id.uuidString.lowercased())"
            return TaskImage(id: reference.id, path: base + ".jpg", thumbPath: base + "_thumb.jpg",
                             width: reference.width, height: reference.height)
        }
    }

    private func startsAt(_ input: TaskInput) -> Date? {
        input.startDate?.date(at: input.startTime, in: TimeZone(identifier: input.timezone) ?? .current)
    }

    func createTask(_ input: TaskInput) async throws(FamiliarError) -> TaskItem {
        let me = try requireUser()
        guard membership(input.familyID, for: me) != nil else {
            throw .app(key: .familyNotFound, message: "Familie nicht gefunden oder du bist kein Mitglied.")
        }
        let task = TaskItem(id: UUID(), familyID: input.familyID, createdBy: me, title: input.title,
                            description: input.description, startDate: input.startDate, startTime: input.startTime,
                            timezone: input.timezone, startsAt: startsAt(input), completionMode: input.completionMode,
                            assignees: input.assigneeIDs.map { TaskAssignee(userID: $0) }, images: images(for: input))
        tasks[task.id] = task
        return task
    }

    func updateTask(id: UUID, expectedVersion: Int, _ input: TaskInput) async throws(FamiliarError) -> TaskItem {
        var task = try visibleTask(id)
        guard task.version == expectedVersion else {
            throw .app(key: .taskConflict, message: "Die Aufgabe wurde inzwischen von jemand anderem geändert. Bitte öffne sie neu.")
        }
        let previous = Dictionary(uniqueKeysWithValues: task.assignees.map { ($0.userID, $0) })
        task.title = input.title
        task.description = input.description
        task.startDate = input.startDate
        task.startTime = input.startTime
        task.startsAt = startsAt(input)
        task.completionMode = input.completionMode
        task.assignees = input.assigneeIDs.map { previous[$0] ?? TaskAssignee(userID: $0) }
        task.images = images(for: TaskInput(familyID: task.familyID, title: "", description: nil, startDate: nil,
                                            startTime: nil, timezone: input.timezone, completionMode: input.completionMode,
                                            assigneeIDs: [], images: input.images))
        task.version += 1
        tasks[id] = task
        return task
    }

    func complete(taskID: UUID, scope: CompletionScope) async throws(FamiliarError) {
        let me = try requireUser()
        var task = try visibleTask(taskID)
        guard let action = TaskRules.actions(for: task, userID: me).first(where: {
            scope == .all ? $0 == .completeForAll || ($0 == .completeForMe && task.completionMode == .anyOne)
                          : $0 == .completeForMe || $0 == .completeForAll
        }) else {
            throw .app(key: .notAllowedToComplete, message: "Nur zugewiesene Personen oder wer die Aufgabe erstellt hat, dürfen sie abhaken.")
        }
        if action == .completeForMe, let index = task.assignees.firstIndex(where: { $0.userID == me }) {
            task.assignees[index].completedAt = .now
        }
        if action == .completeForAll || task.completionMode == .anyOne || task.assignees.allSatisfy(\.isDone) {
            task.completedAt = .now
            task.completedBy = me
            task.completionSource = action == .completeForAll ? .creator : .assignee
        }
        task.version += 1
        tasks[taskID] = task
    }

    func uncomplete(taskID: UUID, scope: CompletionScope) async throws(FamiliarError) {
        let me = try requireUser()
        var task = try visibleTask(taskID)
        if scope == .all || task.completionMode == .anyOne {
            for index in task.assignees.indices { task.assignees[index].completedAt = nil }
        } else if let index = task.assignees.firstIndex(where: { $0.userID == me }) {
            task.assignees[index].completedAt = nil
        }
        task.completedAt = nil
        task.completedBy = nil
        task.completionSource = nil
        task.version += 1
        tasks[taskID] = task
    }

    func delete(taskID: UUID) async throws(FamiliarError) {
        var task = try visibleTask(taskID)
        task.deletedAt = .now
        task.deletedBy = try requireUser()
        task.version += 1
        tasks[taskID] = task
    }

    func restore(taskID: UUID) async throws(FamiliarError) {
        var task = try visibleTask(taskID)
        task.deletedAt = nil
        task.deletedBy = nil
        task.version += 1
        tasks[taskID] = task
    }

    func imageURL(path: String) async throws(FamiliarError) -> URL {
        guard let url = imageFiles[path] else { throw .unknown(message: "Bild nicht gefunden.") }
        return url
    }

    nonisolated func changes(for userID: UUID) -> AsyncStream<UUID> {
        AsyncStream { _ in }
    }
}

extension AppDependencies {
    static func inMemory(scenario: InMemoryBackend.Scenario) -> AppDependencies {
        let backend = InMemoryBackend(scenario: scenario)
        return AppDependencies(auth: backend, profiles: backend, families: backend, tasks: backend)
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
            .environment(TaskStore(repository: dependencies.tasks))
            .environment(TaskImageStore(tasks: dependencies.tasks))
            .preferredColorScheme(.dark)
            .tint(FamiliarColor.accent)
            .task { session.start() }
    }
}
#endif
