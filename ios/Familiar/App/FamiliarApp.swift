import AppIntents
import FamiliarActivity
import FamiliarCore
import FamiliarData
import FamiliarDesign
import SwiftUI

@main
struct FamiliarApp: App {
    @UIApplicationDelegateAdaptor(FamiliarAppDelegate.self) private var appDelegate
    @State private var session: SessionStore
    @State private var avatars: AvatarImageStore
    @State private var tasks: TaskStore
    @State private var taskImages: TaskImageStore
    @State private var outlook: OutlookStore
    @State private var notifications: NotificationStore
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system

    init() {
        FamiliarTypeface.register()
        FamiliarDiagnostics.record("App gestartet")
        let dependencies = AppDependencies.live()
        let session = SessionStore(dependencies: dependencies)
        let tasks = TaskStore(repository: dependencies.tasks)
        let notifications = NotificationStore(devices: dependencies.devices, isEnabled: dependencies.supportsPush)
        session.beforeAccountDeletion = { await GoogleSignInFlow.disconnect() }
        // Widgets zeigen nur Aufgaben des angemeldeten Kontos; nach jeder Abmeldung ist die Liste weg.
        session.onAccountChange = { userID in
            if let userID {
                WidgetSync.activate(userID: userID)
                // Aufgaben schon jetzt laden, parallel zu Profil und Familien (spart einen Rundlauf).
                tasks.prefetch(userID: userID)
            } else {
                WidgetSync.clear()
            }
        }
        session.beforeSignOut = {
            WidgetSync.clear()
            await notifications.signOut()
            GoogleSignInFlow.signOut()
        }
        // Abhaken aus der Live Activity (CompleteTaskIntent läuft im App-Prozess).
        let repository = dependencies.tasks
        TaskCompletionBridge.shared.setHandler { taskID in
            try await repository.complete(taskID: taskID, scope: .me)
            await tasks.reload()
            // Vor dem Ende des Intents: Danach lädt das System die Widgets neu (Apple, „Adding interactivity…“).
            if let userID = session.userID {
                WidgetSync.update(openTasks: tasks.tasks, families: session.families, userID: userID)
            }
        }
        // Siri und Kurzbefehle (ADR 0010) nutzen dieselben Datenquellen.
        IntentEnvironment.dependencies = dependencies
        IntentEnvironment.didChange = {
            await tasks.reload()
            if let userID = session.userID {
                WidgetSync.update(openTasks: tasks.tasks, families: session.families, userID: userID)
            }
        }
        _session = State(initialValue: session)
        _avatars = State(initialValue: AvatarImageStore(profiles: dependencies.profiles))
        _tasks = State(initialValue: tasks)
        _taskImages = State(initialValue: TaskImageStore(tasks: dependencies.tasks))
        _outlook = State(initialValue: OutlookStore(repository: dependencies.calendars))
        _notifications = State(initialValue: notifications)
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // Nur zum Messen: echte System-Tab-Leiste als Maßstab (siehe SystemTabBarReference).
            if ProcessInfo.processInfo.arguments.contains("-FamiliarSystemTabBarReference") {
                SystemTabBarReference()
                    .tint(FamiliarColor.accent)
                    .onChange(of: appearance, initial: true) { appearance.apply() }
            } else {
                appContent
            }
            #else
            appContent
            #endif
        }
    }

    private var appContent: some View {
        RootView()
            .environment(session)
            .environment(avatars)
            .environment(tasks)
            .environment(taskImages)
            .environment(outlook)
            .environment(notifications)
            .tint(FamiliarColor.accent)
            .onChange(of: appearance, initial: true) { appearance.apply() }
            .task {
                appDelegate.notifications = notifications
                session.start()
            }
    }
}
