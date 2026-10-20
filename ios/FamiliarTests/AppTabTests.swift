import Testing
import UIKit
@testable import Familiar

struct AppTabTests {
    @Test func tabsAppearInGuideOrder() {
        #expect(AppTab.allCases == [.tasks, .calendar, .history])
    }

    @Test(arguments: AppTab.allCases)
    func everyTabHasTitleAndExistingSymbol(_ tab: AppTab) {
        #expect(!tab.title.isEmpty)
        #expect(UIImage(systemName: tab.systemImage) != nil)
    }
}
