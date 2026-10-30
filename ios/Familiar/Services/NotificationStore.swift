import ActivityKit
import FamiliarActivity
import FamiliarCore
import Foundation
import Observation
import UIKit
import UserNotifications

/// Mitteilungen und Live Activities auf diesem Gerät (Phase 7, ADR 0005).
///
/// - Meldet das APNs-Geräte-Token und das Push-to-Start-Token beim Server an (`register_device`).
/// - Meldet jede Live Activity mit ihrem Update-Token an (`register_live_activity`), auch solche,
///   die der Server per Push-to-Start gestartet hat; beendete Activities werden abgemeldet.
/// - Gleicht beim Öffnen ab: fehlende Activities starten, veraltete beenden – die Datenbank bleibt
///   maßgeblich, Pushes sind nur Hinweise.
@Observable
final class NotificationStore {
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// Aufgabe, die nach dem Antippen einer Mitteilung geöffnet werden soll.
    var requestedTaskID: UUID?

    private let devices: any DeviceRepository
    private let defaults: UserDefaults
    /// Im In-Memory-Backend (UI-Tests, Previews) weder APNs noch Live Activities.
    private let isEnabled: Bool
    private var userID: UUID?
    private var pushToStartToken: String?
    private var observers: [Task<Void, Never>] = []
    private var observedActivityIDs: Set<String> = []

    private static let tokenKey = "push.deviceToken"

    init(devices: any DeviceRepository, isEnabled: Bool, defaults: UserDefaults = .standard) {
        self.devices = devices
        self.isEnabled = isEnabled
        self.defaults = defaults
    }

    /// Ob Mitteilungen auf diesem Build überhaupt angeboten werden.
    var isAvailable: Bool { isEnabled }

    /// Zuletzt bekanntes APNs-Token dieses Geräts (Hex).
    var deviceToken: String? { defaults.string(forKey: Self.tokenKey) }

    /// Apples Push-Umgebung dieses Builds. Maßgeblich ist, wie die App signiert ist – nicht ob Debug oder Release:
    /// Ein von Xcode installierter Release-Build bekommt ein Sandbox-Token, TestFlight und App Store ein
    /// Produktions-Token. Mit der falschen Angabe lehnt Apple die Mitteilungen ab (BadDeviceToken).
    private var environment: PushEnvironment { Self.currentEnvironment }

    static let currentEnvironment: PushEnvironment = {
        #if targetEnvironment(simulator)
        return .sandbox
        #else
        // Entwicklungs-Builds enthalten das Bereitstellungsprofil mit „aps-environment“; TestFlight und
        // App Store nicht (dort ist es immer Produktion).
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return .production }
        let text = String(decoding: data, as: UTF8.self)
        if let key = text.range(of: "<key>aps-environment</key>"),
           let open = text.range(of: "<string>", range: key.upperBound..<text.endIndex),
           let close = text.range(of: "</string>", range: open.upperBound..<text.endIndex) {
            return text[open.upperBound..<close.lowerBound] == "development" ? .sandbox : .production
        }
        return .production
        #endif
    }()

    /// Ob dies ein Test-Build ist (Xcode oder TestFlight): dort zeigt das Profil die Diagnose.
    /// Nur der App Store legt eine Quittung namens „receipt“ ab; Xcode und TestFlight „sandboxReceipt“.
    static let isTestBuild: Bool = {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent != "receipt"
        #endif
    }()

    // MARK: Anmeldung

    /// Nach der Anmeldung: Token holen und Live Activities beobachten.
    func start(userID: UUID) async {
        guard isEnabled, self.userID != userID else { return }
        stop()
        self.userID = userID
        await refreshAuthorization()
        observeActivities()
        if let token = deviceToken { await register(token: token) }
    }

    func stop() {
        observers.forEach { $0.cancel() }
        observers = []
        observedActivityIDs = []
        userID = nil
    }

    /// Vor dem Abmelden: Gerät abmelden und eigene Activities beenden.
    func signOut() async {
        if let token = deviceToken {
            try? await devices.unregisterDevice(token: token)
        }
        for activity in Activity<TaskActivityAttributes>.activities {
            await Self.endActivity(id: activity.id)
        }
        stop()
    }

    // MARK: Berechtigung

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        // Z. B. in den iOS-Einstellungen eingeschaltet: Token holen (Apple: bei jedem Start erlaubt).
        if isEnabled, userID != nil, authorization == .authorized || authorization == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Fragt die Systemberechtigung ab (nach der Erklärung in ``NotificationPrimerView``).
    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorization()
    }

    /// Ob die Erklärung schon gezeigt wurde (je Konto).
    func hasAskedForPermission(_ userID: UUID) -> Bool {
        defaults.bool(forKey: "push.asked.\(userID.uuidString)")
    }

    func markAskedForPermission(_ userID: UUID) {
        defaults.set(true, forKey: "push.asked.\(userID.uuidString)")
    }

    // MARK: Tokens

    func didRegister(deviceToken data: Data) {
        let token = data.hexString
        FamiliarDiagnostics.record("Geräte-Token erhalten")
        defaults.set(token, forKey: Self.tokenKey)
        Task { await register(token: token) }
    }

    private func register(token: String) async {
        guard userID != nil else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        do {
            try await devices.registerDevice(token: token, environment: environment, pushToStartToken: pushToStartToken,
                                             appVersion: version, timezone: TimeZone.current.identifier)
            FamiliarDiagnostics.record("Gerät angemeldet (\(environment.rawValue), Push-to-Start: \(pushToStartToken == nil ? "nein" : "ja"))")
        } catch {
            FamiliarDiagnostics.record("Geräte-Anmeldung fehlgeschlagen: \(error)")
        }
        // Activities, die vor dem Geräte-Token entstanden sind, jetzt melden.
        for activity in Activity<TaskActivityAttributes>.activities {
            if let updateToken = activity.pushToken {
                await registerActivity(activity, updateToken: updateToken.hexString)
            }
        }
    }

    private func observeActivities() {
        observers.append(Task { [weak self] in
            for await data in Activity<TaskActivityAttributes>.pushToStartTokenUpdates {
                guard let self else { return }
                self.pushToStartToken = data.hexString
                FamiliarDiagnostics.record("Push-to-Start-Token erhalten")
                if let token = self.deviceToken { await self.register(token: token) }
            }
        })
        observers.append(Task { [weak self] in
            for await activity in Activity<TaskActivityAttributes>.activityUpdates {
                self?.observe(activity)
            }
        })
        Activity<TaskActivityAttributes>.activities.forEach(observe)
    }

    private func observe(_ activity: Activity<TaskActivityAttributes>) {
        guard observedActivityIDs.insert(activity.id).inserted else { return }
        FamiliarDiagnostics.record("Live Activity erkannt")
        observers.append(Task { [weak self] in
            for await data in activity.pushTokenUpdates {
                await self?.registerActivity(activity, updateToken: data.hexString)
            }
        })
        observers.append(Task { [weak self] in
            for await state in activity.activityStateUpdates where state == .ended || state == .dismissed {
                guard let self, let token = self.deviceToken else { return }
                try? await self.devices.endLiveActivity(deviceToken: token, activityID: activity.id)
                return
            }
        })
    }

    private func registerActivity(_ activity: Activity<TaskActivityAttributes>, updateToken: String) async {
        guard userID != nil, let token = deviceToken else { return }
        do {
            try await devices.registerLiveActivity(taskID: activity.attributes.taskID, deviceToken: token,
                                                   activityID: activity.id, updateToken: updateToken)
            FamiliarDiagnostics.record("Live Activity beim Server angemeldet")
        } catch {
            FamiliarDiagnostics.record("Live-Activity-Anmeldung fehlgeschlagen: \(error)")
        }
    }

    // MARK: Abgleich

    /// Beim Öffnen und nach jedem Neuladen: fehlende Activities starten, veraltete beenden,
    /// laufende auf den aktuellen Stand bringen.
    func reconcile(openTasks: [TaskItem], families: [FamilyMembership]) async {
        guard isEnabled, let userID, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        var activities = Activity<TaskActivityAttributes>.activities
        // Doppelte Activities derselben Aufgabe (z. B. vom Server per Push gestartet und gleichzeitig lokal):
        // nur eine behalten, sonst erscheinen beim Öffnen zwei Karten, und eine bleibt später hängen.
        var seen: Set<UUID> = []
        for activity in activities where !seen.insert(activity.attributes.taskID).inserted {
            FamiliarDiagnostics.record("Doppelte Live Activity beendet")
            await Self.endActivity(id: activity.id)
        }
        activities = Activity<TaskActivityAttributes>.activities
        let running = Set(activities.map(\.attributes.taskID))
        let plan = LiveActivityRules.reconcile(openTasks: openTasks, running: running, userID: userID)
        let names = Dictionary(families.flatMap(\.members).map { ($0.userID, $0.profile?.displayName ?? "?") },
                               uniquingKeysWith: { first, _ in first })
        let colors = Dictionary(families.map { ($0.family.id, $0.family.colorHex) }, uniquingKeysWith: { first, _ in first })
        let tasksByID = Dictionary(openTasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for activity in activities {
            if plan.end.contains(activity.attributes.taskID) {
                await Self.endActivity(id: activity.id)
            } else if let task = tasksByID[activity.attributes.taskID] {
                let state = TaskActivityAttributes.ContentState(task: task, userID: userID, names: names)
                if state != activity.content.state {
                    await Self.updateActivity(id: activity.id,
                                              content: ActivityContent(state: state, staleDate: Self.staleDate(for: task)))
                }
            }
        }
        if !plan.start.isEmpty || !plan.end.isEmpty {
            FamiliarDiagnostics.record("Abgleich: \(plan.start.count) starten, \(plan.end.count) beenden")
        }
        for task in plan.start {
            let attributes = TaskActivityAttributes(taskID: task.id, familyColorHex: colors[task.familyID] ?? "#FFA43A")
            let state = TaskActivityAttributes.ContentState(task: task, userID: userID, names: names)
            // Fehler (z. B. Systemgrenze erreicht, Activities abgeschaltet) sind nicht kritisch.
            do {
                _ = try Activity.request(attributes: attributes,
                                         content: ActivityContent(state: state, staleDate: Self.staleDate(for: task)),
                                         pushType: .token)
            } catch {
                FamiliarDiagnostics.record("Live Activity konnte nicht starten: \(error)")
            }
        }
    }

    // `Activity` ist nicht `Sendable`: außerhalb des MainActors per ID nachschlagen und ändern.
    nonisolated private static func endActivity(id: String) async {
        guard let activity = Activity<TaskActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    nonisolated private static func updateActivity(id: String,
                                                   content: ActivityContent<TaskActivityAttributes.ContentState>) async {
        guard let activity = Activity<TaskActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(content)
    }

    /// Eine Stunde nach Start gilt die Activity als überfällig (wie `push-dispatch`).
    private static func staleDate(for task: TaskItem) -> Date? {
        task.startTime != nil ? task.startsAt?.addingTimeInterval(LiveActivityRules.startWindow) : nil
    }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

/// Empfängt Geräte-Token und Mitteilungs-Antippen vom System.
final class FamiliarAppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    var notifications: NotificationStore?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        notifications?.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // Ohne Push-Berechtigung im Profil (z. B. Simulator ohne Entwickler-Team): Mitteilungen bleiben aus.
    }

    /// Auch im Vordergrund anzeigen – die Liste aktualisiert sich zusätzlich über Realtime.
    /// Bewusst auf dem MainActor: UIKit ruft den Abschluss dieser async-Methoden auf dem Thread auf, auf dem
    /// sie endet, und stürzt ab („Call must be made on main thread“), wenn das nicht der Hauptthread ist.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let taskID = (response.notification.request.content.userInfo["task_id"] as? String).flatMap(UUID.init(uuidString:))
        if let taskID { notifications?.requestedTaskID = taskID }
    }
}
