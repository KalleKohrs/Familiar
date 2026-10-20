import Testing
@testable import FamiliarCore

struct OnboardingFlowTests {
    @Test func newUserStartsWithProfile() {
        #expect(OnboardingFlow.nextStep(hasFamily: false, profileConfirmed: false) == .profile)
    }

    @Test func confirmedProfileWithoutFamilyAsksForFamily() {
        #expect(OnboardingFlow.nextStep(hasFamily: false, profileConfirmed: true) == .family)
    }

    @Test(arguments: [false, true])
    func familyMemberIsDone(profileConfirmed: Bool) {
        #expect(OnboardingFlow.nextStep(hasFamily: true, profileConfirmed: profileConfirmed) == .done)
    }
}
