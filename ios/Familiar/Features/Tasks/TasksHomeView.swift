import FamiliarCore
import FamiliarDesign
import SwiftUI

/// Startseite „Aufgaben“: offene Aufgaben aller Familien in einer Liste (Guide, Abschnitt 5).
/// Zuerst Aufgaben ohne Datum (neueste oben), dann datierte chronologisch. Keine Filter.
struct TasksHomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(TaskStore.self) private var store
    @Environment(\.openNewTask) private var openNewTask
    @Environment(NotificationStore.self) private var notifications
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var transition
    @State private var path: [UUID] = []
    @State private var gallery: GalleryState?
    @State private var duplicating: TaskItem?
    @State private var showsFamilies = false
    @State private var showsProfile = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
                    header
                    content
                }
                // Weicher Wechsel zwischen Liste und Leerzustand (z. B. nach der letzten Aufgabe).
                .familiarAnimation(value: store.tasks.isEmpty)
                .padding(.horizontal, FamiliarSpacing.m)
                .padding(.top, FamiliarSpacing.s)
            }
            .refreshable { await store.reload() }
            .familiarScreenBackground()
            .navigationTitle("Aufgaben")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
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
            // Mitteilung angetippt: die Aufgabe direkt öffnen.
            .onChange(of: notifications.requestedTaskID, initial: true) { _, taskID in
                guard let taskID else { return }
                showsFamilies = false
                showsProfile = false
                path = [taskID]
                notifications.requestedTaskID = nil
            }
            .sheet(isPresented: $showsFamilies) { FamiliesSheet() }
            .sheet(isPresented: $showsProfile) { ProfileSheet() }
            .sheet(item: $duplicating) { task in
                TaskEditorView(mode: .duplicate(task))
            }
            .fullScreenCover(item: $gallery) { state in
                ImageGalleryView(images: state.images, startIndex: state.index)
            }
        }
    }

    /// Große Überschrift in New York wie in der Design-Referenz.
    private var header: some View {
        Text("Aufgaben")
            .font(FamiliarFont.display)
            .foregroundStyle(FamiliarColor.textPrimary)
            .accessibilityAddTraits(.isHeader)
            .padding(.bottom, FamiliarSpacing.xxs)
    }

    private func sectionTitle(_ section: TaskRules.HomeSection, count: Int) -> some View {
        let title: String = switch section {
        case .overdue: String(localized: "Überfällig")
        case .today: String(localized: "Heute")
        case .tomorrow: String(localized: "Morgen")
        case .later: String(localized: "Später")
        }
        return HStack(spacing: FamiliarSpacing.xs) {
            Text(title)
                .foregroundStyle(section == .overdue ? FamiliarColor.danger : FamiliarColor.textSecondary)
            Text("\(count)")
                .foregroundStyle(FamiliarColor.textSecondary)
                .monospacedDigit()
        }
        .font(FamiliarFont.groupLabel)
        .padding(.top, FamiliarSpacing.s)
        .padding(.leading, FamiliarSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
                if store.hadOpenTasks || !store.history.isEmpty {
                    FamiliarEmptyState(
                        systemImage: "checkmark",
                        title: "Alles erledigt",
                        message: "Gerade ist nichts offen. Neue Aufgaben legst du über das Plus an."
                    )
                    .padding(.vertical, FamiliarSpacing.xl)
                    .transition(FamiliarMotion.appearTransition(reduceMotion: reduceMotion))
                    .accessibilityIdentifier("tasks.allDone")
                } else {
                    FamiliarEmptyState(
                        systemImage: "checklist",
                        title: "Noch keine Aufgaben",
                        message: "Lege über das Plus unten rechts die erste Aufgabe an.",
                        actionTitle: "Aufgabe anlegen",
                        action: { openNewTask() }
                    )
                    .padding(.vertical, FamiliarSpacing.xl)
                    .transition(.opacity)
                }
            } else {
                // Normaler VStack statt LazyVStack: Familienlisten sind kurz, und Ein-/Ausblenden
                // bleibt sauber (LazyVStack ließ ausgeblendete Karten kurz über Überschriften stehen).
                VStack(alignment: .leading, spacing: FamiliarSpacing.s) {
                    ForEach(TaskRules.homeSections(store.tasks), id: \.section) { group in
                        sectionTitle(group.section, count: group.tasks.count)
                            .transition(.opacity)
                        ForEach(group.tasks) { task in
                            TaskCard(
                                task: task,
                                onOpen: { path.append(task.id) },
                                onOpenImages: { gallery = GalleryState(images: task.images, index: 0) },
                                onDuplicate: { duplicating = task }
                            )
                            .matchedTransitionSource(id: task.id, in: transition)
                            .transition(.asymmetric(insertion: .opacity,
                                                    removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))))
                        }
                    }
                }
                .familiarAnimation(value: store.tasks.map(\.id))
                .transition(.opacity)
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

#if DEBUG
#Preview {
    TasksHomeView()
        .previewEnvironment(.ready)
}
#endif
