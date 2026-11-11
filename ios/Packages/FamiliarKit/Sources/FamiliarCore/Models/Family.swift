import Foundation

/// Rolle in einer Familie. Rohwerte wie das Datenbank-Enum `family_role`.
public enum FamilyRole: String, Codable, Hashable, Sendable {
    case admin
    case member
}

/// Sichtbarkeit von Aufgaben in einer Familie. Rohwerte wie das Datenbank-Enum `task_visibility`.
public enum TaskVisibility: String, Codable, Hashable, Sendable {
    case all
    case assignedOnly = "assigned_only"
}

/// Rechte, die ein Admin für Mitglieder einschränken kann (wie `private.has_family_permission`).
public enum FamilyPermission: Hashable, CaseIterable, Sendable {
    case invite
    case manageFamily
    case removeMembers
    case createTasks
    case editTasks
    case deleteTasks
}

/// Eine Familie (`public.families`).
public struct Family: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    /// `#RRGGBB` in Großbuchstaben.
    public var colorHex: String
    public var taskVisibility: TaskVisibility
    public var membersCanInvite: Bool
    public var membersCanManageFamily: Bool
    public var membersCanRemoveMembers: Bool
    public var membersCanCreateTasks: Bool
    public var membersCanEditTasks: Bool
    /// Löschen und Wiederherstellen von Aufgaben.
    public var membersCanDeleteTasks: Bool
    public var createdBy: UUID?

    public init(
        id: UUID,
        name: String,
        colorHex: String,
        taskVisibility: TaskVisibility = .all,
        membersCanInvite: Bool = true,
        membersCanManageFamily: Bool = true,
        membersCanRemoveMembers: Bool = true,
        membersCanCreateTasks: Bool = true,
        membersCanEditTasks: Bool = true,
        membersCanDeleteTasks: Bool = true,
        createdBy: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.taskVisibility = taskVisibility
        self.membersCanInvite = membersCanInvite
        self.membersCanManageFamily = membersCanManageFamily
        self.membersCanRemoveMembers = membersCanRemoveMembers
        self.membersCanCreateTasks = membersCanCreateTasks
        self.membersCanEditTasks = membersCanEditTasks
        self.membersCanDeleteTasks = membersCanDeleteTasks
        self.createdBy = createdBy
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case colorHex = "color_hex"
        case taskVisibility = "task_visibility"
        case membersCanInvite = "members_can_invite"
        case membersCanManageFamily = "members_can_manage_family"
        case membersCanRemoveMembers = "members_can_remove_members"
        case membersCanCreateTasks = "members_can_create_tasks"
        case membersCanEditTasks = "members_can_edit_tasks"
        case membersCanDeleteTasks = "members_can_delete_tasks"
        case createdBy = "created_by"
    }

    // Neue Schalter (Migration 0010) fehlen in älteren Antworten: dann „erlaubt“.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        taskVisibility = try c.decode(TaskVisibility.self, forKey: .taskVisibility)
        membersCanInvite = try c.decodeIfPresent(Bool.self, forKey: .membersCanInvite) ?? true
        membersCanManageFamily = try c.decodeIfPresent(Bool.self, forKey: .membersCanManageFamily) ?? true
        membersCanRemoveMembers = try c.decodeIfPresent(Bool.self, forKey: .membersCanRemoveMembers) ?? true
        membersCanCreateTasks = try c.decodeIfPresent(Bool.self, forKey: .membersCanCreateTasks) ?? true
        membersCanEditTasks = try c.decodeIfPresent(Bool.self, forKey: .membersCanEditTasks) ?? true
        membersCanDeleteTasks = try c.decodeIfPresent(Bool.self, forKey: .membersCanDeleteTasks) ?? true
        createdBy = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
    }

    /// Schalterstand für Mitglieder (Admins dürfen immer alles).
    public func membersMay(_ permission: FamilyPermission) -> Bool {
        switch permission {
        case .invite: membersCanInvite
        case .manageFamily: membersCanManageFamily
        case .removeMembers: membersCanRemoveMembers
        case .createTasks: membersCanCreateTasks
        case .editTasks: membersCanEditTasks
        case .deleteTasks: membersCanDeleteTasks
        }
    }

    public mutating func setMembersMay(_ permission: FamilyPermission, _ allowed: Bool) {
        switch permission {
        case .invite: membersCanInvite = allowed
        case .manageFamily: membersCanManageFamily = allowed
        case .removeMembers: membersCanRemoveMembers = allowed
        case .createTasks: membersCanCreateTasks = allowed
        case .editTasks: membersCanEditTasks = allowed
        case .deleteTasks: membersCanDeleteTasks = allowed
        }
    }

    public var color: RGBColor { RGBColor(hex: colorHex) ?? RGBColor(hex: 0xFF8C42) }
}

/// Mitgliedschaft mit eingebettetem Profil (`family_members?select=*,profiles(*)`).
public struct FamilyMember: Codable, Hashable, Identifiable, Sendable {
    public let familyID: UUID
    public let userID: UUID
    public var role: FamilyRole
    public var joinedAt: Date
    public var profile: Profile?

    public var id: UUID { userID }

    public init(familyID: UUID, userID: UUID, role: FamilyRole, joinedAt: Date = .now, profile: Profile? = nil) {
        self.familyID = familyID
        self.userID = userID
        self.role = role
        self.joinedAt = joinedAt
        self.profile = profile
    }

    enum CodingKeys: String, CodingKey {
        case familyID = "family_id"
        case userID = "user_id"
        case role
        case joinedAt = "joined_at"
        case profile = "profiles"
    }

    public var displayName: String { profile?.displayName ?? String(localized: "Mitglied") }
}

/// Eine Familie aus Sicht des angemeldeten Nutzers: mit Mitgliedern und eigener Rolle.
public struct FamilyMembership: Hashable, Identifiable, Sendable {
    public var family: Family
    public var members: [FamilyMember]
    public let currentUserID: UUID

    public var id: UUID { family.id }

    public init(family: Family, members: [FamilyMember], currentUserID: UUID) {
        self.family = family
        self.members = members
        self.currentUserID = currentUserID
    }

    public var myRole: FamilyRole? { members.first { $0.userID == currentUserID }?.role }

    /// Mitglieder sortiert: Admins zuerst, dann nach Name.
    public var sortedMembers: [FamilyMember] {
        members.sorted {
            if $0.role != $1.role { return $0.role == .admin }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    /// Spiegelt `private.has_family_permission`: Admins dürfen alles, Mitglieder je nach Schalter.
    public func allows(_ permission: FamilyPermission) -> Bool {
        switch myRole {
        case .admin: true
        case .member: family.membersMay(permission)
        case nil: false
        }
    }

    /// Allein in der Familie: Dann lohnt der Hinweis „Hol deine Familie dazu“.
    public var isOnlyMember: Bool { members.count <= 1 }

    /// Soll die Startseite zum Einladen auffordern? Nur wer allein ist und einladen darf.
    public var suggestsInvite: Bool { myRole != nil && isOnlyMember && allows(.invite) }

    /// Der letzte Admin darf nicht gehen, solange andere Mitglieder da sind (wie `leave_family`).
    public var isLastAdminWithOthers: Bool {
        myRole == .admin
            && members.count > 1
            && members.filter { $0.role == .admin }.count == 1
    }
}
