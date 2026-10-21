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

    init() {
        FamiliarTypeface.register()
        let dependencies = AppDependencies.live()
        let session = SessionStore(dependencies: dependencies)
        let tasks = TaskStore(repository: dependencies.tasks)
        let notifications = NotificationStore(devices: dependencies.devices, isEnabled: dependencies.supportsPush)
        session.beforeSignOut = {
            await notifications.signOut()
            GoogleSignInFlow.signOut()
        }
        // Abhaken aus der Live Activity (CompleteTaskIntent läuft im App-Prozess).
        let repository = dependencies.tasks
        TaskCompletionBridge.shared.setHandler { taskID in
            try await repository.complete(taskID: taskID, scope: .me)
            await tasks.reload()
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
            RootView()
                .environment(session)
                .environment(avatars)
                .environment(tasks)
                .environment(taskImages)
                .environment(outlook)
                .environment(notifications)
                .preferredColorScheme(.dark)
                .tint(FamiliarColor.accent)
                .task {
                    appDelegate.notifications = notifications
                    session.start()
                }
        }
    }
}

/// Bindet die App Intents aus FamiliarActivity (Abhaken in der Live Activity) in die App ein.
struct FamiliarAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [FamiliarActivityIntents.self] }
}
