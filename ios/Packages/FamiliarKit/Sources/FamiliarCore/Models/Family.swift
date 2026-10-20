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
public enum FamilyPermission: Hashable, Sendable {
    case invite
    case manageFamily
    case removeMembers
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
    public var createdBy: UUID?

    public init(
        id: UUID,
        name: String,
        colorHex: String,
        taskVisibility: TaskVisibility = .all,
        membersCanInvite: Bool = true,
        membersCanManageFamily: Bool = true,
        membersCanRemoveMembers: Bool = true,
        createdBy: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.taskVisibility = taskVisibility
        self.membersCanInvite = membersCanInvite
        self.membersCanManageFamily = membersCanManageFamily
        self.membersCanRemoveMembers = membersCanRemoveMembers
        self.createdBy = createdBy
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case colorHex = "color_hex"
        case taskVisibility = "task_visibility"
        case membersCanInvite = "members_can_invite"
        case membersCanManageFamily = "members_can_manage_family"
        case membersCanRemoveMembers = "members_can_remove_members"
        case createdBy = "created_by"
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
        case .member:
            switch permission {
            case .invite: family.membersCanInvite
            case .manageFamily: family.membersCanManageFamily
            case .removeMembers: family.membersCanRemoveMembers
            }
        case nil: false
        }
    }

    /// Der letzte Admin darf nicht gehen, solange andere Mitglieder da sind (wie `leave_family`).
    public var isLastAdminWithOthers: Bool {
        myRole == .admin
            && members.count > 1
            && members.filter { $0.role == .admin }.count == 1
    }
}
