import FamiliarCore
import Foundation
import Supabase
import Testing
@testable import FamiliarData

/// Antworten im Format von PostgREST, dekodiert mit dem Decoder des SDK.
struct DecodingTests {
    let decoder = PostgrestClient.Configuration.jsonDecoder

    @Test func familyWithEmbeddedMembersAndProfiles() throws {
        let json = """
        [{
          "id": "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b",
          "name": "Familie Test",
          "color_hex": "#5EC2F2",
          "task_visibility": "assigned_only",
          "members_can_invite": true,
          "members_can_manage_family": false,
          "members_can_remove_members": true,
          "created_by": "a1111111-1111-4111-8111-111111111111",
          "created_at": "2026-10-20T18:28:58.123456+00:00",
          "updated_at": "2026-10-20T18:28:58.123456+00:00",
          "family_members": [{
            "family_id": "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b",
            "user_id": "a1111111-1111-4111-8111-111111111111",
            "role": "admin",
            "joined_at": "2026-10-20T18:28:58.5+00:00",
            "profiles": {
              "id": "a1111111-1111-4111-8111-111111111111",
              "display_name": "Olivia",
              "avatar_path": "a1111111-1111-4111-8111-111111111111/avatar.jpg",
              "created_at": "2026-10-20T18:00:00+00:00",
              "updated_at": "2026-10-20T18:30:00+00:00"
            }
          }]
        }]
        """
        let rows = try decoder.decode([FamilyRow].self, from: Data(json.utf8))
        let row = try #require(rows.first)
        #expect(row.family.name == "Familie Test")
        #expect(row.family.taskVisibility == .assignedOnly)
        #expect(!row.family.membersCanManageFamily)
        #expect(row.members.count == 1)
        #expect(row.members.first?.role == .admin)
        #expect(row.members.first?.profile?.displayName == "Olivia")
        #expect(row.members.first?.profile?.avatarPath?.hasSuffix("/avatar.jpg") == true)
    }

    @Test func joinResultWithoutFamily() throws {
        let json = """
        {"status": "rate_limited", "family_id": null, "retry_after_seconds": 1800,
         "message": "Zu viele Fehlversuche. Bitte versuche es später erneut."}
        """
        let result = try decoder.decode(JoinFamilyResult.self, from: Data(json.utf8))
        #expect(result.status == .rateLimited)
        #expect(result.retryAfterSeconds == 1800)
        #expect(!result.isSuccess)
    }

    @Test func inviteAndLeaveResult() throws {
        let invite = """
        {"id": "0b1c2d3e-4f50-4a6b-8c7d-8e9f0a1b2c3d", "family_id": "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b",
         "code": "7K3M9P2Q", "created_by": null, "created_at": "2026-10-20T18:28:58+00:00",
         "expires_at": "2026-10-27T18:28:58+00:00", "revoked_at": null, "use_count": 0}
        """
        let decoded = try decoder.decode(FamilyInvite.self, from: Data(invite.utf8))
        #expect(decoded.code == "7K3M9P2Q")
        #expect(decoded.isActive(at: Date(timeIntervalSince1970: 0)))
        #expect(try decoder.decode(LeaveFamilyResult.self, from: Data(#""family_deleted""#.utf8)) == .familyDeleted)
    }
}
