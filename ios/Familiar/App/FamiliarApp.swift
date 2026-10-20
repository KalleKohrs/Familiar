import FamiliarDesign
import SwiftUI

@main
struct FamiliarApp: App {
    @State private var session: SessionStore
    @State private var avatars: AvatarImageStore

    init() {
        let dependencies = AppDependencies.live()
        _session = State(initialValue: SessionStore(dependencies: dependencies))
        _avatars = State(initialValue: AvatarImageStore(profiles: dependencies.profiles))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(avatars)
                .preferredColorScheme(.dark)
                .tint(FamiliarColor.accent)
                .task { session.start() }
        }
    }
}
