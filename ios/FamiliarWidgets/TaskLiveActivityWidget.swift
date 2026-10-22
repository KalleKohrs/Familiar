import ActivityKit
import AppIntents
import FamiliarActivity
import FamiliarCore
import FamiliarDesign
import SwiftUI
import WidgetKit

/// Live Activity einer Aufgabe auf Sperrbildschirm und in der Dynamic Island.
/// Gestartet per Push-to-Start (`push-dispatch`) oder beim Abgleich in der App; der Abhak-Knopf
/// erscheint nur, wenn die Person laut Erledigungsart abhaken darf (`canComplete`).
struct TaskLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TaskActivityAttributes.self) { context in
            TaskActivityLockScreenView(context: context)
                .activityBackgroundTint(FamiliarColor.canvas)
                .activitySystemActionForegroundColor(FamiliarColor.accent)
        } dynamicIsland: { context in
            let familyColor = context.attributes.familyColor
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "checklist")
                        .foregroundStyle(familyColor)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // Abstand zur Rundung der Insel, sonst wird die Uhrzeit angeschnitten.
                    StartTimeText(startsAt: context.state.startsAt)
                        .fixedSize()
                        .padding(.trailing, FamiliarSpacing.xs)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        AssigneeInitialsRow(assignees: context.state.assignees)
                        Spacer(minLength: 0)
                        if context.state.canComplete {
                            CompleteButton(taskID: context.attributes.taskID)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "checklist")
                    .foregroundStyle(familyColor)
            } compactTrailing: {
                StartTimeText(startsAt: context.state.startsAt)
            } minimal: {
                Image(systemName: "checklist")
                    .foregroundStyle(familyColor)
            }
            .keylineTint(familyColor)
        }
    }
}

private struct TaskActivityLockScreenView: View {
    let context: ActivityViewContext<TaskActivityAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: FamiliarSpacing.s) {
            Capsule()
                .fill(context.attributes.familyColor)
                .frame(width: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: FamiliarSpacing.xxs) {
                Text(context.state.title)
                    .font(.headline)
                    .foregroundStyle(FamiliarColor.textPrimary)
                    .lineLimit(2)
                HStack(spacing: FamiliarSpacing.xs) {
                    StartTimeText(startsAt: context.state.startsAt)
                    if context.isStale {
                        Text("Überfällig")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FamiliarColor.danger)
                    }
                }
                AssigneeInitialsRow(assignees: context.state.assignees)
            }
            Spacer(minLength: 0)
            if context.state.canComplete {
                CompleteButton(taskID: context.attributes.taskID)
            }
        }
        .padding(FamiliarSpacing.m)
    }
}

private struct StartTimeText: View {
    let startsAt: Date?

    var body: some View {
        if let startsAt {
            Text(startsAt, style: .time)
                .font(.footnote.monospacedDigit().weight(.medium))
                .foregroundStyle(FamiliarColor.textSecondary)
        } else {
            Text("Heute")
                .font(.footnote.weight(.medium))
                .foregroundStyle(FamiliarColor.textSecondary)
        }
    }
}

/// Abhaken ohne die App zu öffnen (``CompleteTaskIntent`` läuft im App-Prozess).
private struct CompleteButton: View {
    let taskID: UUID

    var body: some View {
        Button(intent: CompleteTaskIntent(taskID: taskID)) {
            Image(systemName: "checkmark")
                .font(.body.weight(.bold))
                .foregroundStyle(FamiliarColor.onAccent)
                .frame(width: 44, height: 44)
                .background(Circle().fill(FamiliarColor.accentFill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Erledigt")
    }
}

private struct AssigneeInitialsRow: View {
    let assignees: [TaskActivityAttributes.AssigneeState]

    var body: some View {
        HStack(spacing: FamiliarSpacing.xs) {
            ForEach(Array(assignees.prefix(6).enumerated()), id: \.offset) { _, assignee in
                // Wie in der App: erledigt = grüner Ring mit Haken, nicht abgeblendet.
                Text(assignee.initials)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(FamiliarColor.textPrimary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(FamiliarColor.elevated))
                    .overlay {
                        if assignee.isDone {
                            Circle().strokeBorder(FamiliarColor.success, lineWidth: 1.5)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if assignee.isDone {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(FamiliarColor.onAccent, FamiliarColor.success)
                                .offset(x: 3, y: 3)
                        }
                    }
                    .accessibilityLabel("\(assignee.initials), \(assignee.isDone ? "erledigt" : "offen")")
            }
        }
    }
}

extension TaskActivityAttributes {
    var familyColor: Color {
        Color(RGBColor(hex: familyColorHex) ?? RGBColor(hex: 0xFFA43A))
    }
}

#Preview("Sperrbildschirm", as: .content, using: TaskActivityAttributes(taskID: UUID(), familyColorHex: "#5EC2F2")) {
    TaskLiveActivityWidget()
} contentStates: {
    TaskActivityAttributes.ContentState(
        title: "Müll rausbringen",
        startsAtUnix: Date.now.addingTimeInterval(300).timeIntervalSince1970,
        completionMode: .each,
        assignees: [.init(initials: "AB", isDone: true), .init(initials: "BB", isDone: false)],
        canComplete: true
    )
}
