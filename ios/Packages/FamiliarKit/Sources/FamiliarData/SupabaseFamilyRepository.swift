import FamiliarCore
import Foundation
import Supabase

final class SupabaseFamilyRepository: FamilyRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func myFamilies() async throws(FamiliarError) -> [FamilyMembership] {
        let userID = try await client.currentUserID()
        // RLS liefert nur Familien, in denen der Nutzer Mitglied ist, samt aller Mitglieder.
        let rows: [FamilyRow] = try await perform {
            try await client.from("families")
                .select("*, family_members(*, profiles(*))")
                .execute()
                .value
        }
        return rows
            .map { FamilyMembership(family: $0.family, members: $0.members, currentUserID: userID) }
            .sorted { $0.family.name.localizedStandardCompare($1.family.name) == .orderedAscending }
    }

    func createFamily(name: String, colorHex: String) async throws(FamiliarError) -> Family {
        try await perform {
            try await client.rpc(
                "create_family",
                params: ["p_name": InputRules.trimmed(name), "p_color_hex": colorHex]
            ).execute().value
        }
    }

    func joinFamily(code: String) async throws(FamiliarError) -> JoinFamilyResult {
        try await perform {
            try await client.rpc("join_family", params: ["p_code": InviteCode.normalize(code)]).execute().value
        }
    }

    func createInvite(familyID: UUID) async throws(FamiliarError) -> FamilyInvite {
        try await perform {
            try await client.rpc("create_invite", params: ["p_family_id": familyID]).execute().value
        }
    }

    func leaveFamily(familyID: UUID) async throws(FamiliarError) -> LeaveFamilyResult {
        try await perform {
            try await client.rpc("leave_family", params: ["p_family_id": familyID]).execute().value
        }
    }

    func updateFamily(familyID: UUID, name: String, colorHex: String, visibility: TaskVisibility) async throws(FamiliarError) {
        let params = UpdateFamilyParams(familyID: familyID, name: InputRules.trimmed(name), colorHex: colorHex,
                                        visibility: visibility)
        _ = try await perform {
            try await client.rpc("update_family", params: params).execute()
        }
    }

    func setPermissions(familyID: UUID, _ changes: [FamilyPermission: Bool]) async throws(FamiliarError) {
        var params: [String: AnyJSON] = ["p_family_id": .string(familyID.uuidString)]
        for (permission, allowed) in changes {
            params[Self.parameter(for: permission)] = .bool(allowed)
        }
        _ = try await perform {
            try await client.rpc("set_family_permissions", params: params).execute()
        }
    }

    func setMemberRole(familyID: UUID, userID: UUID, role: FamilyRole) async throws(FamiliarError) {
        _ = try await perform {
            try await client.rpc("set_member_role", params: [
                "p_family_id": familyID.uuidString, "p_user_id": userID.uuidString, "p_role": role.rawValue,
            ]).execute()
        }
    }

    func removeMember(familyID: UUID, userID: UUID) async throws(FamiliarError) {
        _ = try await perform {
            try await client.rpc("remove_member", params: [
                "p_family_id": familyID.uuidString, "p_user_id": userID.uuidString,
            ]).execute()
        }
    }

    func deleteFamily(familyID: UUID) async throws(FamiliarError) {
        _ = try await perform {
            try await client.rpc("delete_family", params: ["p_family_id": familyID.uuidString]).execute()
        }
    }

    /// Parametername in `set_family_permissions` (Migration 0010).
    static func parameter(for permission: FamilyPermission) -> String {
        switch permission {
        case .invite: "p_members_can_invite"
        case .manageFamily: "p_members_can_manage_family"
        case .removeMembers: "p_members_can_remove_members"
        case .createTasks: "p_members_can_create_tasks"
        case .editTasks: "p_members_can_edit_tasks"
        case .deleteTasks: "p_members_can_delete_tasks"
        }
    }
}

private struct UpdateFamilyParams: Encodable {
    let familyID: UUID
    let name: String
    let colorHex: String
    let visibility: TaskVisibility

    enum CodingKeys: String, CodingKey {
        case familyID = "p_family_id"
        case name = "p_name"
        case colorHex = "p_color_hex"
        case visibility = "p_task_visibility"
    }
}

/// Zeile aus `families` mit eingebetteten Mitgliedern.
struct FamilyRow: Decodable {
    let family: Family
    let members: [FamilyMember]

    private enum CodingKeys: String, CodingKey {
        case members = "family_members"
    }

    init(from decoder: any Decoder) throws {
        family = try Family(from: decoder)
        members = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent([FamilyMember].self, forKey: .members) ?? []
    }
}
