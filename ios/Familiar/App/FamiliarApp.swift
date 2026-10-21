import FamiliarDesign
import SwiftUI

@main
struct FamiliarApp: App {
    @State private var session: SessionStore
    @State private var avatars: AvatarImageStore
    @State private var tasks: TaskStore
    @State private var taskImages: TaskImageStore

    init() {
        let dependencies = AppDependencies.live()
        _session = State(initialValue: SessionStore(dependencies: dependencies))
        _avatars = State(initialValue: AvatarImageStore(profiles: dependencies.profiles))
        _tasks = State(initialValue: TaskStore(repository: dependencies.tasks))
        _taskImages = State(initialValue: TaskImageStore(tasks: dependencies.tasks))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(avatars)
                .environment(tasks)
                .environment(taskImages)
                .preferredColorScheme(.dark)
                .tint(FamiliarColor.accent)
                .task { session.start() }
        }
    }
}
