import FamiliarCore
import FamiliarDesign
import SwiftUI

/// Startseite „Aufgaben“: offene Aufgaben aller Familien in einer Liste (Guide, Abschnitt 5).
/// Zuerst Aufgaben ohne Datum (neueste oben), dann datierte chronologisch. Keine Filter.
struct TasksHomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var store
    @Environment(\.openNewTask) private var openNewTask
    @Namespace private var transition
    @State private var path: [UUID] = []
    @State private var gallery: GalleryState?
    @State private var showsFamilies = false
    @State private var showsProfile = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: FamiliarSpacing.s) {
                    content
                    #if DEBUG
                    NavigationLink("Design-System ansehen") {
                        DesignGalleryView()
                    }
                    .buttonStyle(.familiarSecondary)
                    .padding(.top, FamiliarSpacing.l)
                    #endif
                }
                .padding(.horizontal, FamiliarSpacing.m)
                .padding(.top, FamiliarSpacing.s)
            }
            .refreshable { await store.reload() }
            .familiarScreenBackground()
            .navigationTitle("Aufgaben")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    FamilyHeaderButton(title: session.familyHeaderTitle) { showsFamilies = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileHeaderButton { showsProfile = true }
                }
            }
            .navigationDestination(for: UUID.self) { taskID in
                TaskDetailView(taskID: taskID)
                    .navigationTransition(.zoom(sourceID: taskID, in: transition))
            }
            .overlay(alignment: .bottom) { TaskBanner() }
            .sheet(isPresented: $showsFamilies) { FamiliesSheet() }
            .sheet(isPresented: $showsProfile) { ProfileSheet() }
            .fullScreenCover(item: $gallery) { state in
                ImageGalleryView(images: state.images, startIndex: state.index)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.tasks.isEmpty && (store.state == .idle || store.state == .loading) {
            ForEach(0..<3, id: \.self) { _ in FamiliarSkeleton(height: 104) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Aufgaben werden geladen")
        } else if store.tasks.isEmpty, case .failed(let error) = store.state {
            FamiliarErrorState(message: error.message) {
                Task { await store.reload() }
            }
            .familiarCard()
        } else {
            if store.tasks.isEmpty {
                FamiliarEmptyState(
                    systemImage: "checklist",
                    title: "Noch keine Aufgaben",
                    message: "Lege über das Plus unten rechts die erste Aufgabe an.",
                    actionTitle: "Aufgabe anlegen",
                    action: { openNewTask() }
                )
                .familiarCard()
            } else {
                LazyVStack(spacing: FamiliarSpacing.s) {
                    ForEach(store.tasks) { task in
                        TaskCard(
                            task: task,
                            onOpen: { path.append(task.id) },
                            onOpenImages: { gallery = GalleryState(images: task.images, index: 0) }
                        )
                        .matchedTransitionSource(id: task.id, in: transition)
                    }
                }
                .familiarAnimation(value: store.tasks.map(\.id))
            }
        }
    }
}

/// Bildansicht mit Startbild.
struct GalleryState: Identifiable {
    let id = UUID()
    let images: [TaskImage]
    let index: Int
}

/// Familienname oben links; öffnet das Sheet „Familien“ (Plan, Abschnitt 6).
struct FamilyHeaderButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: FamiliarSpacing.xxs) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .foregroundStyle(FamiliarColor.textPrimary)
        }
        .accessibilityLabel("\(title), Familien verwalten")
        .accessibilityIdentifier("header.family")
    }
}

/// Eigenes Profilbild oben rechts; öffnet Profil und Einstellungen.
struct ProfileHeaderButton: View {
    @Environment(SessionStore.self) private var session
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ProfileAvatar(profile: session.profile, name: session.profile?.displayName ?? "", diameter: 30)
        }
        .accessibilityLabel("Profil und Einstellungen")
        .accessibilityIdentifier("header.profile")
    }
}

#Preview {
    TasksHomeView()
        .previewEnvironment(.ready)
}
