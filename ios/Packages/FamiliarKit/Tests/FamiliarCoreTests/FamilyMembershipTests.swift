import Foundation
import Testing
@testable import FamiliarCore

struct FamilyMembershipTests {
    let me = UUID()
    let other = UUID()
    let familyID = UUID()

    func membership(myRole: FamilyRole, otherRole: FamilyRole? = nil, family: Family? = nil) -> FamilyMembership {
        var members = [FamilyMember(familyID: familyID, userID: me, role: myRole, profile: Profile(id: me, displayName: "Zoe"))]
        if let otherRole {
            members.append(FamilyMember(familyID: familyID, userID: other, role: otherRole, profile: Profile(id: other, displayName: "Anna")))
        }
        return FamilyMembership(
            family: family ?? Family(id: familyID, name: "Test", colorHex: "#5EC2F2"),
            members: members,
            currentUserID: me
        )
    }

    @Test func adminMayEverything() {
        let restricted = Family(id: familyID, name: "Test", colorHex: "#5EC2F2",
                                membersCanInvite: false, membersCanManageFamily: false, membersCanRemoveMembers: false)
        let admin = membership(myRole: .admin, family: restricted)
        #expect(admin.allows(.invite) && admin.allows(.manageFamily) && admin.allows(.removeMembers))
    }

    @Test func memberFollowsFamilySwitches() {
        let family = Family(id: familyID, name: "Test", colorHex: "#5EC2F2",
                            membersCanInvite: true, membersCanManageFamily: false, membersCanRemoveMembers: false)
        let member = membership(myRole: .member, otherRole: .admin, family: family)
        #expect(member.allows(.invite))
        #expect(!member.allows(.manageFamily))
        #expect(!member.allows(.removeMembers))
    }

    @Test func nonMemberMayNothing() {
        let family = Family(id: familyID, name: "Test", colorHex: "#5EC2F2")
        let membership = FamilyMembership(family: family, members: [], currentUserID: me)
        #expect(membership.myRole == nil)
        #expect(!membership.allows(.invite))
    }

    @Test func lastAdminWithOthersCannotLeave() {
        #expect(membership(myRole: .admin, otherRole: .member).isLastAdminWithOthers)
        #expect(!membership(myRole: .admin, otherRole: .admin).isLastAdminWithOthers)
        #expect(!membership(myRole: .admin).isLastAdminWithOthers)
        #expect(!membership(myRole: .member, otherRole: .admin).isLastAdminWithOthers)
    }

    @Test func sortsAdminsFirstThenByName() {
        let sorted = membership(myRole: .member, otherRole: .admin).sortedMembers
        #expect(sorted.map(\.displayName) == ["Anna", "Zoe"])
    }

    @Test func avatarPathUsesLowercaseUserID() {
        let id = UUID(uuidString: "A1111111-1111-4111-8111-111111111111")!
        #expect(Profile.avatarStoragePath(for: id) == "a1111111-1111-4111-8111-111111111111/avatar.jpg")
    }
}
