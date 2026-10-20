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
