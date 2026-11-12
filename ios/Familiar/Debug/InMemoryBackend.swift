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
        /// Angemeldet, eine Familie, noch keine Aufgaben und niemand sonst dabei (wie ein frisches Konto).
        case empty
        /// Vorführdaten für App-Store-Bilder: zwei Familien, neutrale Namen, abwechslungsreiche Aufgaben.
        case showcase

        static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> Scenario {
            guard let index = arguments.firstIndex(of: "-FamiliarInMemoryScenario"),
                  arguments.indices.contains(index + 1) else { return .signedOut }
            return Scenario(rawValue: arguments[index + 1]) ?? .signedOut
        }
    }

    static let validEmailCode = "123456"
    /// `-FamiliarLiveActivities`: lokale Live Activities zur Sichtprüfung (ohne Server und Push).
    static let liveActivitiesDemo = ProcessInfo.processInfo.arguments.contains("-FamiliarLiveActivities")
    static let joinableCode = "TEST2345"
    /// `-FamiliarInMemoryLatency <ms>`: künstliche Netzverzögerung beim Laden der Listen – damit lassen sich
    /// Ladezustände und Übergänge (Platzhalter, Leerzustand) wie mit echtem Netz prüfen.
    private static let latency: Duration = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-FamiliarInMemoryLatency"), arguments.indices.contains(index + 1),
              let milliseconds = Int(arguments[index + 1]) else { return .zero }
        return .milliseconds(milliseconds)
    }()

    /// Beginn der ersten Anfrage: Nullpunkt für das Anfrage-Protokoll.
    private static let origin = ContinuousClock.now

    private func simulateLatency(_ name: String = #function) async {
        guard Self.latency > .zero else { return }
        // Protokoll für Messungen: zeigt, welche Anfragen nacheinander und welche gleichzeitig laufen.
        func stamp() -> Int { Int((ContinuousClock.now - Self.origin) / .milliseconds(1)) }
        NSLog("NETZ %@ Start %d ms", name, stamp())
        try? await Task.sleep(for: Self.latency)
        NSLog("NETZ %@ Ende %d ms", name, stamp())
    }

    private var user: (id: UUID, email: String)?
    private var profiles: [UUID: Profile] = [:]
    private var families: [UUID: Family] = [:]
    private var members: [UUID: [FamilyMember]] = [:]
    private var invites: [String: FamilyInvite] = [:]
    private var avatarFiles: [String: URL] = [:]
    private var listeners: [UUID: AsyncStream<AuthState>.Continuation] = [:]
    private var tasks: [UUID: TaskItem] = [:]
    private var imageFiles: [String: URL] = [:]
    private var seriesRecords: [UUID: SeriesRecord] = [:]
    private var deletions: [UUID: SeriesDeletion] = [:]
    /// Anstupsen: letzter Zeitpunkt je Aufgabe und Person (Grenze 1 Stunde wie `nudge_task`).
    private var nudges: [String: Date] = [:]
    /// Für Tests: angelegte Erinnerungen (Aufgabe, Empfänger).
    private(set) var sentNudges: [(taskID: UUID, userID: UUID)] = []

    /// Serie mit Vorlage für neue Vorkommen und Wasserstandsmarke (wie `task_series`).
    private struct SeriesRecord {
        var info: TaskSeries
        var input: TaskInput
        var createdBy: UUID
        var generatedUntil: LocalDate?
        var resumeFrom: LocalDate?
    }

    init(scenario: Scenario) {
        let anna = UUID()
        profiles[anna] = Profile(id: anna, displayName: "Anna")
        let example = Family(id: UUID(), name: "Familie Beispiel", colorHex: "#8FD19E", createdBy: anna)
        families[example.id] = example
        members[example.id] = [FamilyMember(familyID: example.id, userID: anna, role: .admin, profile: profiles[anna])]
        invites[Self.joinableCode] = FamilyInvite(id: UUID(), familyID: example.id, code: Self.joinableCode,
                                                  expiresAt: .now.addingTimeInterval(7 * 24 * 3600))

        if scenario == .showcase {
            let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current
            let today = LocalDate(.now, timeZone: berlin)
            let me = UUID(), jonas = UUID(), mia = UUID(), paul = UUID(), ruth = UUID()
            user = (me, "lena@example.test")
            var showcaseProfiles: [UUID: Profile] = [:]
            for (id, name) in [(me, "Lena"), (jonas, "Jonas"), (mia, "Mia"), (paul, "Paul"), (ruth, "Ruth")] {
                showcaseProfiles[id] = Profile(id: id, displayName: name)
            }
            profiles.merge(showcaseProfiles) { _, new in new }
            let berger = Family(id: UUID(), name: "Familie Berger", colorHex: "#5EC2F2",
                                membersCanManageFamily: false, membersCanRemoveMembers: false,
                                membersCanDeleteTasks: false, createdBy: me)
            let grandparents = Family(id: UUID(), name: "Oma & Opa", colorHex: "#F7C548", createdBy: ruth)
            families[berger.id] = berger
            families[grandparents.id] = grandparents
            var bergerMembers: [FamilyMember] = []
            for id in [me, jonas, mia, paul] {
                bergerMembers.append(FamilyMember(familyID: berger.id, userID: id,
                                                  role: id == me || id == jonas ? .admin : .member,
                                                  profile: showcaseProfiles[id]))
            }
            var grandparentMembers: [FamilyMember] = []
            for id in [ruth, me, jonas] {
                grandparentMembers.append(FamilyMember(familyID: grandparents.id, userID: id,
                                                       role: id == ruth ? .admin : .member, profile: showcaseProfiles[id]))
            }
            members[berger.id] = bergerMembers
            members[grandparents.id] = grandparentMembers
            func at(_ days: Int, _ hour: Int, _ minute: Int = 0) -> (LocalDate, LocalTime, Date) {
                let date = today.adding(days: days), time = LocalTime(hour: hour, minute: minute)
                return (date, time, date.date(at: time, in: berlin))
            }
            let dentist = at(1, 15, 30), football = at(2, 17), lawn = at(3, 10)
            let items = [
                TaskItem(id: UUID(), familyID: berger.id, createdBy: me, title: "Zimmer aufräumen",
                         description: "Jede Person ihr eigenes Zimmer.", startDate: today, completionMode: .each,
                         assignees: [TaskAssignee(userID: mia, completedAt: .now), TaskAssignee(userID: paul)]),
                TaskItem(id: UUID(), familyID: grandparents.id, createdBy: ruth, title: "Geschenk für Opa besorgen",
                         description: "Er wünscht sich ein Vogelhaus.", completionMode: .anyOne,
                         createdAt: .now.addingTimeInterval(-3600),
                         assignees: [TaskAssignee(userID: me), TaskAssignee(userID: jonas)]),
                TaskItem(id: UUID(), familyID: berger.id, createdBy: jonas, title: "Müll rausbringen", startDate: today,
                         completionMode: .anyOne, assignees: [TaskAssignee(userID: paul)]),
                TaskItem(id: UUID(), familyID: berger.id, createdBy: me, title: "Zahnarzt Paul", startDate: dentist.0,
                         startTime: dentist.1, startsAt: dentist.2, completionMode: .anyOne,
                         assignees: [TaskAssignee(userID: me)]),
                TaskItem(id: UUID(), familyID: berger.id, createdBy: me, title: "Mia vom Fußball abholen",
                         startDate: football.0, startTime: football.1, startsAt: football.2, completionMode: .anyOne,
                         assignees: [TaskAssignee(userID: jonas)]),
                TaskItem(id: UUID(), familyID: grandparents.id, createdBy: ruth, title: "Rasen mähen",
                         startDate: lawn.0, startTime: lawn.1, startsAt: lawn.2, completionMode: .anyOne,
                         assignees: [TaskAssignee(userID: jonas)]),
                TaskItem(id: UUID(), familyID: berger.id, createdBy: jonas, title: "Einkaufen",
                         description: "Milch, Brot, Äpfel", completionMode: .anyOne,
                         completedAt: .now.addingTimeInterval(-7200), completedBy: me, completionSource: .assignee,
                         createdAt: .now.addingTimeInterval(-86400), assignees: [TaskAssignee(userID: me)]),
                TaskItem(id: UUID(), familyID: berger.id, createdBy: me, title: "Elternabend Klasse 3b",
                         startDate: today.adding(days: 6), completionMode: .anyOne,
                         deletedAt: .now.addingTimeInterval(-1800), deletedBy: paul,
                         createdAt: .now.addingTimeInterval(-172_800), assignees: [TaskAssignee(userID: me)]),
                TaskItem(id: UUID(), familyID: berger.id, createdBy: jonas, title: "Spülmaschine ausräumen",
                         completionMode: .anyOne, completedAt: .now.addingTimeInterval(-86400 - 3600),
                         completedBy: mia, completionSource: .assignee,
                         createdAt: .now.addingTimeInterval(-172_800), assignees: [TaskAssignee(userID: mia)]),
                TaskItem(id: UUID(), familyID: grandparents.id, createdBy: ruth, title: "Blumen gießen",
                         completionMode: .anyOne, completedAt: .now.addingTimeInterval(-86400 - 18000),
                         completedBy: jonas, completionSource: .assignee,
                         createdAt: .now.addingTimeInterval(-259_200), assignees: [TaskAssignee(userID: jonas)]),
            ]
            for item in items { tasks[item.id] = item }
            let lunchRule = RecurrenceRule.weekly([1, 2, 3, 4, 5])
            let lunch = TaskInput(familyID: berger.id, title: "Pausenbrote machen", description: nil,
                                  startDate: today.adding(days: 1), startTime: LocalTime(hour: 7, minute: 15),
                                  timezone: "Europe/Berlin", completionMode: .anyOne, assigneeIDs: [jonas], images: [],
                                  recurrence: lunchRule)
            let lunchInfo = TaskSeries(id: UUID(), familyID: berger.id, title: "Pausenbrote machen", rule: lunchRule,
                                       startDate: lunch.startDate)
            seriesRecords[lunchInfo.id] = SeriesRecord(info: lunchInfo, input: lunch, createdBy: me)
        }

        if scenario == .empty {
            let me = UUID()
            user = (me, "kalle@example.test")
            profiles[me] = Profile(id: me, displayName: "Kalle")
            let family = Family(id: UUID(), name: "Lindner", colorHex: "#FF7F66", createdBy: me)
            families[family.id] = family
            members[family.id] = [FamilyMember(familyID: family.id, userID: me, role: .admin, profile: profiles[me])]
        }

        if scenario == .ready {
            let me = UUID()
            user = (me, "kalle@example.test")
            profiles[me] = Profile(id: me, displayName: "Kalle")
            let family = Family(id: UUID(), name: "Familie Lindner", colorHex: "#FF7F66", createdBy: me)
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

            // Für den Kalender: ein Termin morgen und eine wöchentliche Serie (Di und Do).
            let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current
            let tomorrow = LocalDate(.now, timeZone: berlin).adding(days: 1)
            let doctor = TaskItem(id: UUID(), familyID: family.id, createdBy: me, title: "Arzttermin Anna",
                                  startDate: tomorrow, startTime: LocalTime(hour: 15, minute: 30),
                                  startsAt: tomorrow.date(at: LocalTime(hour: 15, minute: 30), in: berlin),
                                  completionMode: .anyOne, assignees: [TaskAssignee(userID: anna)])
            tasks[doctor.id] = doctor
            if Self.liveActivitiesDemo {
                // Sichtprüfung der Live Activity: eine Aufgabe, die in drei Minuten beginnt.
                let soon = Date.now.addingTimeInterval(180)
                let today = LocalDate(soon, timeZone: berlin)
                let time = LocalTime(soon, timeZone: berlin)
                let pickup = TaskItem(id: UUID(), familyID: family.id, createdBy: anna, title: "Kinder abholen",
                                      startDate: today, startTime: time, startsAt: today.date(at: time, in: berlin),
                                      completionMode: .each,
                                      assignees: [TaskAssignee(userID: me), TaskAssignee(userID: anna, completedAt: .now)])
                tasks[pickup.id] = pickup
            }
            let trainingRule = RecurrenceRule.weekly([2, 4])
            let training = TaskInput(familyID: family.id, title: "Training", description: nil,
                                     startDate: LocalDate(.now, timeZone: berlin), startTime: LocalTime(hour: 18, minute: 0),
                                     timezone: "Europe/Berlin", completionMode: .anyOne, assigneeIDs: [me], images: [],
                                     recurrence: trainingRule)
            let trainingInfo = TaskSeries(id: UUID(), familyID: family.id, title: "Training", rule: trainingRule,
                                          startDate: training.startDate)
            seriesRecords[trainingInfo.id] = SeriesRecord(info: trainingInfo, input: training, createdBy: me)
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

    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws(FamiliarError) {
        let id = UUID()
        profiles[id] = Profile(id: id, displayName: fullName ?? "Apple-Konto")
        user = (id, "apple@privaterelay.example")
        publish()
    }

    func signInWithGoogle(idToken: String, accessToken: String, nonce: String) async throws(FamiliarError) {
        let id = UUID()
        profiles[id] = Profile(id: id, displayName: "Google-Konto")
        user = (id, "google@example.test")
        publish()
    }

    func isLinkedToApple() async -> Bool { false }

    func deleteAccount(appleAuthorizationCode: String?) async throws(FamiliarError) {
        let me = try requireUser()
        for (familyID, familyMembers) in members where familyMembers.contains(where: { $0.userID == me }) {
            let others = familyMembers.filter { $0.userID != me }
            if others.isEmpty {
                families[familyID] = nil
                members[familyID] = nil
            } else {
                var remaining = others
                if !remaining.contains(where: { $0.role == .admin }), let index = remaining.indices.first {
                    remaining[index].role = .admin
                }
                members[familyID] = remaining
            }
        }
        profiles[me] = nil
        user = nil
        publish()
    }
}

extension InMemoryBackend: ProfileRepository {
    func myProfile() async throws(FamiliarError) -> Profile {
        await simulateLatency()
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
        await simulateLatency()
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
        handleDeparture(of: id, from: familyID)
        return .left
    }

    /// Wie `private.handle_member_departure` (Migration 0018): Wer austritt, ist für nichts mehr
    /// zuständig; Reihum-Termine ohne Person gehen an die Person, die nach der Regel dran ist.
    private func handleDeparture(of userID: UUID, from familyID: UUID) {
        // Private Aufgaben und Serien gehören der austretenden Person allein und verschwinden mit ihr (ADR 0012).
        for (id, record) in seriesRecords where record.input.isPrivate && record.input.familyID == familyID
            && record.createdBy == userID {
            seriesRecords[id] = nil
        }
        for (id, task) in tasks where task.isPrivate && task.familyID == familyID && task.createdBy == userID {
            tasks[id] = nil
        }
        for (seriesID, var record) in seriesRecords where record.input.familyID == familyID {
            record.input.assigneeIDs.removeAll { $0 == userID }
            record.info.assigneeOrder.removeAll { $0 == userID }
            seriesRecords[seriesID] = record
        }
        for var task in tasks.values where task.familyID == familyID && task.isOpen {
            let before = task.assignees
            task.assignees.removeAll { $0.userID == userID && !$0.isDone }
            if task.assignees.isEmpty, let seriesID = task.seriesID, let record = seriesRecords[seriesID],
               record.info.isRotating, let date = task.occurrenceDate {
                task.assignees = occurrenceAssignees(record, on: date).map { TaskAssignee(userID: $0) }
            }
            if task.completionMode == .each, !task.assignees.isEmpty, task.assignees.allSatisfy(\.isDone) {
                task.completedAt = .now
                task.completedBy = task.assignees.max { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }?.userID
                task.completionSource = .assignee
            }
            guard task.assignees != before || task.completedAt != nil else { continue }
            task.series = task.seriesID.flatMap { seriesRecords[$0]?.info } ?? task.series
            task.version += 1
            tasks[task.id] = task
        }
    }
}


extension InMemoryBackend {
    private func requireMembership(_ familyID: UUID) throws(FamiliarError) -> FamilyMembership {
        let me = try requireUser()
        guard let membership = membership(familyID, for: me) else {
            throw .app(key: .familyNotFound, message: "Familie nicht gefunden oder du bist kein Mitglied.")
        }
        return membership
    }

    private func requireAdmin(_ familyID: UUID) throws(FamiliarError) {
        guard try requireMembership(familyID).myRole == .admin else {
            throw .app(key: .adminRequired, message: "Nur Admins dürfen das.")
        }
    }

    func updateFamily(familyID: UUID, name: String, colorHex: String, visibility: TaskVisibility) async throws(FamiliarError) {
        guard try requireMembership(familyID).allows(.manageFamily) else {
            throw .app(key: .permissionDeniedManageFamily, message: "Du darfst diese Familie nicht bearbeiten.")
        }
        families[familyID]?.name = name
        families[familyID]?.colorHex = colorHex
        families[familyID]?.taskVisibility = visibility
    }

    func setPermissions(familyID: UUID, _ changes: [FamilyPermission: Bool]) async throws(FamiliarError) {
        try requireAdmin(familyID)
        for (permission, allowed) in changes { families[familyID]?.setMembersMay(permission, allowed) }
    }

    func setMemberRole(familyID: UUID, userID: UUID, role: FamilyRole) async throws(FamiliarError) {
        try requireAdmin(familyID)
        let admins = members[familyID]?.filter { $0.role == .admin } ?? []
        if role == .member, admins.count == 1, admins.first?.userID == userID {
            throw .app(key: .lastAdmin, message: "Die Familie braucht mindestens einen Admin. Ernenne zuerst eine andere Person zum Admin.")
        }
        if let index = members[familyID]?.firstIndex(where: { $0.userID == userID }) {
            members[familyID]?[index].role = role
        }
    }

    func removeMember(familyID: UUID, userID: UUID) async throws(FamiliarError) {
        guard try requireMembership(familyID).allows(.removeMembers) else {
            throw .app(key: .permissionDeniedRemoveMembers, message: "Du darfst in dieser Familie keine Mitglieder entfernen.")
        }
        members[familyID]?.removeAll { $0.userID == userID }
        handleDeparture(of: userID, from: familyID)
    }

    func deleteFamily(familyID: UUID) async throws(FamiliarError) {
        try requireAdmin(familyID)
        families[familyID] = nil
        members[familyID] = nil
        for task in tasks.values where task.familyID == familyID { tasks[task.id] = nil }
    }
}

extension InMemoryBackend: TaskRepository {
    /// Wie `private.can_view_task` (Migration 0021): Private Aufgaben sieht nur ihr Ersteller.
    private func canView(_ task: TaskItem, _ me: UUID) -> Bool {
        membership(task.familyID, for: me) != nil && (!task.isPrivate || task.createdBy == me)
    }

    private func visibleTask(_ id: UUID) throws(FamiliarError) -> TaskItem {
        let me = try requireUser()
        guard let task = tasks[id], canView(task, me) else {
            throw .app(key: .taskNotFound, message: "Aufgabe nicht gefunden oder für dich nicht sichtbar.")
        }
        return task
    }

    func openTasks() async throws(FamiliarError) -> [TaskItem] {
        await simulateLatency()
        let me = try requireUser()
        generateAll()
        return tasks.values.filter { $0.isOpen && canView($0, me) }
    }

    func task(id: UUID) async throws(FamiliarError) -> TaskItem {
        try visibleTask(id)
    }

    func historyTasks() async throws(FamiliarError) -> [TaskItem] {
        await simulateLatency()
        let me = try requireUser()
        return HistoryRules.entries(tasks.values.filter { !$0.isOpen && canView($0, me) })
    }

    // MARK: Serien (vereinfacht nach Migration 0009)

    private func today(_ timezone: String) -> LocalDate {
        LocalDate(.now, timeZone: TimeZone(identifier: timezone) ?? .current)
    }

    /// Wie der Cron-Job auf dem Server: alle Serien fortschreiben.
    private func generateAll() {
        for id in seriesRecords.keys { generate(id) }
    }

    /// Vorkommen bis heute plus das nächste künftige; nie vor der Wasserstandsmarke.
    private func generate(_ seriesID: UUID) {
        guard var record = seriesRecords[seriesID], record.info.deletedAt == nil, let rule = record.input.recurrence,
              let start = record.info.startDate else { return }
        let today = today(record.input.timezone)
        let from = [start, record.resumeFrom, record.generatedUntil?.adding(days: 1)].compactMap { $0 }.max() ?? start
        var dates = from <= today ? rule.dates(from: from, through: today) : []
        if record.generatedUntil.map({ $0 <= today }) ?? true,
           let next = rule.firstDate(onOrAfter: max(from, today.adding(days: 1))) {
            dates.append(next)
        }
        for date in dates where !tasks.values.contains(where: { $0.seriesID == seriesID && $0.occurrenceDate == date }) {
            var input = record.input
            input.startDate = date
            let task = TaskItem(id: UUID(), familyID: input.familyID, createdBy: record.createdBy, title: input.title,
                                description: input.description, startDate: date, startTime: input.startTime,
                                timezone: input.timezone, startsAt: startsAt(input), completionMode: input.completionMode,
                                assignees: occurrenceAssignees(record, on: date).map { TaskAssignee(userID: $0) },
                                images: images(for: input), seriesID: seriesID, occurrenceDate: date, series: record.info,
                                isPrivate: record.input.isPrivate)
            tasks[task.id] = task
        }
        if let last = dates.last {
            record.generatedUntil = max(record.generatedUntil ?? last, last)
            seriesRecords[seriesID] = record
        }
    }

    /// Wie `private.occurrence_assignees`: alle Zugewiesenen oder bei „Reihum“ die Person, die dran ist.
    private func occurrenceAssignees(_ record: SeriesRecord, on date: LocalDate) -> [UUID] {
        let memberIDs = Set((members[record.input.familyID] ?? []).map(\.userID))
        if record.info.isRotating {
            return record.info.rotationPerson(on: date, members: memberIDs).map { [$0] } ?? []
        }
        return record.input.assigneeIDs.filter(memberIDs.contains)
    }

    /// Wie `private.validate_rotation`: Reihum braucht zwei Personen und gilt immer als „eine Person“.
    private func validatedRotation(_ input: TaskInput) throws(FamiliarError) -> TaskInput {
        guard input.assignmentMode == .rotate else { return input }
        guard Set(input.assigneeIDs).count >= 2 else {
            throw .app(key: .rotationNeedsTwo, message: "Für „Reihum“ braucht es mindestens zwei Personen.")
        }
        var input = input
        input.completionMode = .anyOne
        return input
    }

    /// Private Serien: nur der Ersteller, nie Reihum (wie create_recurring_task/update_series_from).
    private func privateSeriesInput(_ input: TaskInput, owner: UUID) -> TaskInput {
        var input = input
        input.assigneeIDs = [owner]
        input.assignmentMode = .together
        input.rotationUnit = .occurrence
        return input
    }

    func createSeries(_ input: TaskInput) async throws(FamiliarError) {
        let me = try requireUser()
        guard membership(input.familyID, for: me) != nil else {
            throw .app(key: .familyNotFound, message: "Familie nicht gefunden oder du bist kein Mitglied.")
        }
        guard let rule = input.recurrence?.normalized, rule.isComplete, let start = input.startDate else {
            throw .app(key: .invalidRecurrence, message: "Bitte wähle für die Wiederholung mindestens einen Wochentag bzw. Monatstag.")
        }
        let today = today(input.timezone)
        var normalizedInput = try validatedRotation(input.isPrivate ? privateSeriesInput(input, owner: me) : input)
        normalizedInput.recurrence = rule
        let info = TaskSeries(id: UUID(), familyID: input.familyID, title: input.title, rule: rule, startDate: start,
                              assignmentMode: normalizedInput.assignmentMode, rotationUnit: normalizedInput.rotationUnit,
                              rotationStart: RotationRules.start(rule: rule, startDate: start, today: today),
                              assigneeOrder: normalizedInput.assigneeIDs)
        seriesRecords[info.id] = SeriesRecord(info: info, input: normalizedInput, createdBy: me,
                                              generatedUntil: start < today ? today.adding(days: -1) : nil)
        generate(info.id)
    }

    func updateSeries(fromTaskID taskID: UUID, expectedVersion: Int, _ originalInput: TaskInput) async throws(FamiliarError) -> TaskItem {
        let task = try visibleTask(taskID)
        var originalInput = originalInput
        if task.isPrivate, let owner = task.createdBy {
            originalInput = privateSeriesInput(originalInput, owner: owner)
            originalInput.isPrivate = true
        }
        let input = try validatedRotation(originalInput)
        guard let seriesID = task.seriesID, var record = seriesRecords[seriesID],
              let occurrenceDate = task.occurrenceDate else {
            throw .app(key: .notAnOccurrence, message: "Diese Aufgabe gehört zu keiner Serie.")
        }
        guard let rule = input.recurrence?.normalized, rule.isComplete else {
            throw .app(key: .invalidRecurrence, message: "Bitte wähle für die Wiederholung mindestens einen Wochentag bzw. Monatstag.")
        }
        let ruleChanged = rule != record.info.rule
        let today = today(input.timezone)
        record.info.title = input.title
        record.info.rule = rule
        record.info.assignmentMode = input.assignmentMode
        record.info.rotationUnit = input.rotationUnit
        record.info.rotationStart = occurrenceDate
        record.info.assigneeOrder = input.assigneeIDs
        record.input = input
        record.input.recurrence = rule
        seriesRecords[seriesID] = record

        var updated = try await updateTask(id: taskID, expectedVersion: expectedVersion, input)
        updated.series = record.info
        updated.assignees = occurrenceAssignees(record, on: occurrenceDate).map { TaskAssignee(userID: $0) }
        updated.isDetached = task.isDetached // „Dieses und zukünftige“ koppelt nicht ab
        tasks[taskID] = updated
        let later = tasks.values.filter {
            $0.seriesID == seriesID && ($0.occurrenceDate ?? occurrenceDate) > occurrenceDate && $0.isOpen
                && !$0.isDetached && !$0.assignees.contains(where: \.isDone)
        }
        for var other in later {
            if ruleChanged, let date = other.occurrenceDate, date > today {
                tasks[other.id] = nil
            } else {
                var otherInput = input
                otherInput.startDate = other.startDate
                other.title = input.title
                other.description = input.description
                other.startTime = input.startTime
                other.startsAt = startsAt(otherInput)
                other.completionMode = input.completionMode
                other.assignees = occurrenceAssignees(record, on: other.occurrenceDate ?? occurrenceDate)
                    .map { TaskAssignee(userID: $0) }
                other.images = images(for: input)
                other.series = record.info
                other.version += 1
                tasks[other.id] = other
            }
        }
        if ruleChanged {
            let remaining = tasks.values.filter { $0.seriesID == seriesID }.compactMap(\.occurrenceDate).max()
            seriesRecords[seriesID]?.generatedUntil = [occurrenceDate, today, remaining].compactMap { $0 }.max()
        }
        generate(seriesID)
        return tasks[taskID] ?? updated
    }

    func deleteSeries(fromTaskID taskID: UUID) async throws(FamiliarError) -> UUID {
        let me = try requireUser()
        let task = try visibleTask(taskID)
        guard let seriesID = task.seriesID, var record = seriesRecords[seriesID] else {
            throw .app(key: .notAnOccurrence, message: "Diese Aufgabe gehört zu keiner Serie.")
        }
        let deletion = SeriesDeletion(id: UUID(), seriesID: seriesID, familyID: task.familyID, deletedBy: me,
                                      deletedAt: .now, series: record.info)
        deletions[deletion.id] = deletion
        record.info.deletedAt = deletion.deletedAt
        seriesRecords[seriesID] = record
        for var other in tasks.values where other.seriesID == seriesID && other.isOpen {
            other.deletedAt = deletion.deletedAt
            other.deletedBy = me
            other.deletedBySeriesOp = deletion.id
            other.version += 1
            tasks[other.id] = other
        }
        return deletion.id
    }

    func restoreSeries(deletionID: UUID) async throws(FamiliarError) {
        guard var deletion = deletions[deletionID], var record = seriesRecords[deletion.seriesID] else {
            throw .app(key: .seriesDeletionNotFound, message: "Dieser Verlaufseintrag existiert nicht mehr.")
        }
        guard deletion.restoredAt == nil else { return }
        for var other in tasks.values where other.deletedBySeriesOp == deletionID {
            other.deletedAt = nil
            other.deletedBy = nil
            other.deletedBySeriesOp = nil
            other.version += 1
            tasks[other.id] = other
        }
        record.info.deletedAt = nil
        record.resumeFrom = today(record.input.timezone)
        seriesRecords[deletion.seriesID] = record
        deletion.restoredAt = .now
        deletions[deletionID] = deletion
        generate(deletion.seriesID)
    }

    func clearHistory() async throws(FamiliarError) {
        let me = try requireUser()
        let adminFamilies = Set(families.keys.filter { membership($0, for: me)?.myRole == .admin })
        guard !adminFamilies.isEmpty else {
            throw .app(key: .adminRequired, message: "Nur Admins dürfen das.")
        }
        for (id, record) in seriesRecords where record.info.familyID.map(adminFamilies.contains) == true && record.info.deletedAt != nil
            && (!record.input.isPrivate || record.createdBy == me) {
            seriesRecords[id] = nil
        }
        for (id, task) in tasks where adminFamilies.contains(task.familyID) && (task.completedAt != nil || task.deletedAt != nil)
            && (!task.isPrivate || task.createdBy == me) {
            tasks[id] = nil
        }
        for (id, deletion) in deletions where adminFamilies.contains(deletion.familyID) {
            deletions[id] = nil
        }
    }

    func purge(taskID: UUID) async throws(FamiliarError) {
        let task = try visibleTask(taskID)
        guard task.completedAt != nil || task.deletedAt != nil else {
            throw .app(key: .taskNotFound, message: "Diese Aufgabe steht nicht im Verlauf.")
        }
        guard task.deletedBySeriesOp == nil else {
            throw .app(key: .restoreSeriesInstead, message: "Diese Aufgabe gehört zu einer gelöschten Serie.")
        }
        tasks[taskID] = nil
    }

    func purgeSeriesDeletion(deletionID: UUID) async throws(FamiliarError) {
        guard let deletion = deletions[deletionID] else {
            throw .app(key: .seriesDeletionNotFound, message: "Dieser Verlaufseintrag existiert nicht mehr.")
        }
        for (id, task) in tasks where task.deletedBySeriesOp == deletionID { tasks[id] = nil }
        deletions[deletionID] = nil
        if seriesRecords[deletion.seriesID]?.info.deletedAt != nil { seriesRecords[deletion.seriesID] = nil }
    }

    func calendarTasks(from: LocalDate, through: LocalDate) async throws(FamiliarError) -> [TaskItem] {
        await simulateLatency()
        let me = try requireUser()
        generateAll()
        return tasks.values.filter { task in
            guard task.deletedAt == nil, let date = task.startDate, canView(task, me) else { return false }
            return date >= from && date <= through
        }
    }

    func projectedOccurrences(from: LocalDate, through: LocalDate) async throws(FamiliarError) -> [ProjectedOccurrence] {
        await simulateLatency()
        let me = try requireUser()
        return seriesRecords.values.flatMap { record -> [ProjectedOccurrence] in
            guard record.info.deletedAt == nil, membership(record.input.familyID, for: me) != nil,
                  !record.input.isPrivate || record.createdBy == me,
                  let rule = record.input.recurrence, let start = record.info.startDate else { return [] }
            let lower = [from, start, record.resumeFrom, record.generatedUntil?.adding(days: 1)].compactMap { $0 }.max() ?? from
            guard lower <= through else { return [] }
            return rule.dates(from: lower, through: through).map { date in
                ProjectedOccurrence(seriesID: record.info.id, familyID: record.input.familyID, date: date,
                                    startTime: record.input.startTime, timezone: record.input.timezone,
                                    title: record.input.title, rule: rule,
                                    rotationPerson: occurrenceAssignees(record, on: date).first.flatMap {
                                        record.info.isRotating ? $0 : nil
                                    })
            }
        }
    }

    func nudge(taskID: UUID, userID: UUID) async throws(FamiliarError) -> NudgeResult {
        let me = try requireUser()
        let task = try visibleTask(taskID)
        guard userID != me else {
            throw .app(key: .nudgeSelf, message: "Du kannst dich nicht selbst erinnern.")
        }
        guard task.isOpen else {
            throw .app(key: .nudgeNotOpen, message: "Für diese Person ist die Aufgabe nicht mehr offen.")
        }
        guard membership(task.familyID, for: userID) != nil else {
            throw .app(key: .memberNotFound, message: "Diese Person ist kein Mitglied der Familie.")
        }
        guard task.assignees.contains(where: { $0.userID == userID && !$0.isDone }) else {
            throw .app(key: .nudgeNotOpen, message: "Für diese Person ist die Aufgabe nicht mehr offen.")
        }
        let key = "\(taskID)-\(userID)"
        if let last = nudges[key], Date.now.timeIntervalSince(last) < 3600 {
            throw .app(key: .nudgeTooSoon, message: "Diese Person wurde in der letzten Stunde schon erinnert. Versuche es später noch einmal.")
        }
        nudges[key] = .now
        sentNudges.append((taskID, userID))
        return NudgeResult(scheduledFor: .now, quietHours: false)
    }

    func seriesDeletions() async throws(FamiliarError) -> [SeriesDeletion] {
        await simulateLatency()
        let me = try requireUser()
        return deletions.values.filter { $0.restoredAt == nil && membership($0.familyID, for: me) != nil }
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
        // Privat: gehört dem Ersteller, er ist der Einzige, dem die Aufgabe zugewiesen ist (wie create_task).
        let assigneeIDs = input.isPrivate ? [me] : input.assigneeIDs
        let task = TaskItem(id: UUID(), familyID: input.familyID, createdBy: me, title: input.title,
                            description: input.description, startDate: input.startDate, startTime: input.startTime,
                            timezone: input.timezone, startsAt: startsAt(input), completionMode: input.completionMode,
                            assignees: assigneeIDs.map { TaskAssignee(userID: $0) }, images: images(for: input),
                            isPrivate: input.isPrivate)
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
        let assigneeIDs = task.isPrivate ? (task.createdBy.map { [$0] } ?? []) : input.assigneeIDs
        task.assignees = assigneeIDs.map { previous[$0] ?? TaskAssignee(userID: $0) }
        task.images = images(for: TaskInput(familyID: task.familyID, title: "", description: nil, startDate: nil,
                                            startTime: nil, timezone: input.timezone, completionMode: input.completionMode,
                                            assigneeIDs: [], images: input.images))
        task.isDetached = task.isDetached || task.isOccurrence
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
        guard task.deletedBySeriesOp == nil else {
            throw .app(key: .restoreSeriesInstead,
                       message: "Dieses Vorkommen wurde mit der ganzen Serie gelöscht. Stelle die Serie im Verlauf wieder her.")
        }
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

/// Outlook ohne Netzwerk: mit `-FamiliarInMemoryOutlook` ist ein Firmenkonto verbunden,
/// mit einem Termin morgen um 9:00 und einem ganztägigen Termin übermorgen.
actor InMemoryCalendars: ExternalCalendarRepository {
    private var connection: CalendarConnection?
    private var storedEvents: [ExternalEvent] = []

    init(connected: Bool) {
        guard connected else { return }
        let calendar = ExternalCalendar(id: UUID(), name: "Kalender", isDefault: true, isSelected: true)
        connection = CalendarConnection(id: UUID(), accountEmail: "kalle@firma.example", status: .active,
                                        lastSyncAt: .now, calendars: [calendar,
                                            ExternalCalendar(id: UUID(), name: "Geburtstage")])
        let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current
        let tomorrow = LocalDate(.now, timeZone: berlin).adding(days: 1)
        let meetingStart = tomorrow.date(at: LocalTime(hour: 9, minute: 0), in: berlin)
        let dayAfter = tomorrow.adding(days: 1)
        storedEvents = [
            ExternalEvent(id: UUID(), calendarID: calendar.id, provider: "outlook", title: "Team-Meeting",
                          startsAt: meetingStart, endsAt: meetingStart.addingTimeInterval(3600), isAllDay: false,
                          location: "Raum 3", organizerName: "Chefin"),
            ExternalEvent(id: UUID(), calendarID: calendar.id, provider: "outlook", title: "Messe",
                          startsAt: dayAfter.startOfDay(in: berlin), endsAt: dayAfter.adding(days: 1).startOfDay(in: berlin),
                          isAllDay: true, startDate: dayAfter, endDate: dayAfter.adding(days: 1)),
        ]
    }

    func connections() async throws(FamiliarError) -> [CalendarConnection] {
        connection.map { [$0] } ?? []
    }

    func connectLinks() async throws(FamiliarError) -> CalendarConnectLinks {
        throw .unknown(message: "Im Testmodus nicht verfügbar.")
    }

    func setSelected(calendarID: UUID, _ selected: Bool) async throws(FamiliarError) {
        guard let index = connection?.calendars.firstIndex(where: { $0.id == calendarID }) else { return }
        connection?.calendars[index].isSelected = selected
    }

    func disconnect(connectionID: UUID) async throws(FamiliarError) {
        connection = nil
        storedEvents = []
    }

    func requestSync() async throws(FamiliarError) -> Bool {
        connection != nil
    }

    func events(from: Date, to: Date) async throws(FamiliarError) -> [ExternalEvent] {
        let selected = Set(connection?.calendars.filter(\.isSelected).map(\.id) ?? [])
        return storedEvents.filter { event in
            event.startsAt < to && event.endsAt > from && event.calendarID.map(selected.contains) ?? false
        }
    }
}

extension AppDependencies {
    static func inMemory(scenario: InMemoryBackend.Scenario) -> AppDependencies {
        let backend = InMemoryBackend(scenario: scenario)
        return AppDependencies(auth: backend, profiles: backend, families: backend, tasks: backend,
                               calendars: InMemoryCalendars(
                                   connected: ProcessInfo.processInfo.arguments.contains("-FamiliarInMemoryOutlook")),
                               devices: InMemoryDevices(), supportsPush: InMemoryBackend.liveActivitiesDemo)
    }
}

extension View {
    /// Umgebung für Xcode-Previews mit dem In-Memory-Backend.
    func previewEnvironment(_ scenario: InMemoryBackend.Scenario) -> some View {
        FamiliarTypeface.register()
        let dependencies = AppDependencies.inMemory(scenario: scenario)
        let session = SessionStore(dependencies: dependencies, defaults: UserDefaults(suiteName: "preview") ?? .standard)
        return self
            .environment(session)
            .environment(AvatarImageStore(profiles: dependencies.profiles))
            .environment(TaskStore(repository: dependencies.tasks))
            .environment(TaskImageStore(tasks: dependencies.tasks))
            .environment(OutlookStore(repository: dependencies.calendars))
            .environment(NotificationStore(devices: dependencies.devices, isEnabled: false))
            .preferredColorScheme(.dark)
            .tint(FamiliarColor.accent)
            .task { session.start() }
    }
}

/// Geräte ohne Server: Mitteilungen gibt es im In-Memory-Backend nicht.
struct InMemoryDevices: DeviceRepository {
    func registerDevice(token: String, environment: PushEnvironment, pushToStartToken: String?,
                        appVersion: String?, timezone: String?) async throws(FamiliarError) {}
    func unregisterDevice(token: String) async throws(FamiliarError) {}
    func registerLiveActivity(taskID: UUID, deviceToken: String, activityID: String,
                              updateToken: String) async throws(FamiliarError) {}
    func endLiveActivity(deviceToken: String, activityID: String) async throws(FamiliarError) {}
}
#endif
