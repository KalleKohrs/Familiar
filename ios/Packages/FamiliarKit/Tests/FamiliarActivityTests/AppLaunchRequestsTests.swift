import Foundation
import Testing
@testable import FamiliarActivity

@MainActor
struct AppLaunchRequestsTests {
    final class Counter: @unchecked Sendable { var value = 0 }

    @Test func requestRunsHandlerImmediatelyWhenReady() {
        let requests = AppLaunchRequests()
        let counter = Counter()
        requests.setNewTaskHandler { counter.value += 1 }
        requests.requestNewTask()
        #expect(counter.value == 1)
    }

    @Test func earlyRequestIsRunOnceWhenAppBecomesReady() {
        let requests = AppLaunchRequests()
        let counter = Counter()
        let now = Date.now
        requests.requestNewTask(now: now)
        requests.setNewTaskHandler({ counter.value += 1 }, now: now.addingTimeInterval(5))
        #expect(counter.value == 1)
        // Eine zweite Anmeldung (z. B. nach Tab-Wechsel) führt die alte Anfrage nicht noch einmal aus.
        requests.setNewTaskHandler({ counter.value += 1 }, now: now.addingTimeInterval(6))
        #expect(counter.value == 1)
    }

    @Test func staleRequestIsDropped() {
        let requests = AppLaunchRequests()
        let counter = Counter()
        let now = Date.now
        requests.requestNewTask(now: now)
        requests.setNewTaskHandler({ counter.value += 1 }, now: now.addingTimeInterval(AppLaunchRequests.validity + 1))
        #expect(counter.value == 0)
    }

    @Test func noHandlerMeansNothingHappens() {
        let requests = AppLaunchRequests()
        let counter = Counter()
        requests.setNewTaskHandler { counter.value += 1 }
        requests.setNewTaskHandler(nil)
        requests.requestNewTask()
        #expect(counter.value == 0)
        // Die Anfrage ist vorgemerkt und läuft, sobald die App wieder bereit ist.
        requests.setNewTaskHandler { counter.value += 1 }
        #expect(counter.value == 1)
    }
}
