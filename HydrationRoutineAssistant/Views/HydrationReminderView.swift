import SwiftUI
import UIKit

struct HydrationReminderView: View {
    @Environment(HydrationWorkspaceViewModel.self) private var model
    @ScaledMetric(relativeTo: .body) private var choiceWidth: CGFloat = 90

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Use this reminder routine", isOn: $model.routineEnabled)
                Text("Save an enabled routine to allow notifications and schedule your water breaks.")
                    .font(.callout).foregroundStyle(HydrationTheme.supportingText)
            } header: { Text("Your routine").foregroundStyle(HydrationTheme.supportingText) }
            Section {
                Text(model.notificationPermission.title)
                Text("\(model.scheduledReminderCount) upcoming water-break reminders")
                    .foregroundStyle(HydrationTheme.supportingText)
                if let next = model.nextReminderDate {
                    Text("Next: \(next.formatted(date: .abbreviated, time: .shortened))")
                        .font(.callout)
                }
                if model.notificationPermission == .denied,
                   let settings = URL(string: UIApplication.openNotificationSettingsURLString) {
                    Link("Open notification settings", destination: settings).frame(minHeight: 44)
                }
            } header: { Text("Notification status").foregroundStyle(HydrationTheme.supportingText) }
            Section {
                DatePicker("Start time", selection: $model.routineStart, displayedComponents: .hourAndMinute)
                DatePicker("End time", selection: $model.routineEnd, displayedComponents: .hourAndMinute)
                Stepper("Every \(model.routineInterval) minutes", value: $model.routineInterval, in: 15...180, step: 15)
            } header: { Text("Reminder window").foregroundStyle(HydrationTheme.supportingText) }
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: min(choiceWidth, 280)))], spacing: 8) {
                    ForEach(HydrationWeekday.displayOrder) { day in
                        let selected = model.routineWeekdays.contains(day.rawValue)
                        Button { model.toggleWeekday(day) } label: {
                            Label(day.shortTitle, systemImage: selected ? "checkmark.circle.fill" : "circle")
                                .frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(day.title)
                        .accessibilityValue(selected ? "Selected" : "Not selected")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                Button("Select weekdays") { model.routineWeekdays = [2, 3, 4, 5, 6]; model.clearRoutineFeedback() }
                    .frame(minHeight: 44)
            } header: { Text("Routine days").foregroundStyle(HydrationTheme.supportingText) }
            if let issue = model.routineIssue { Section { HydrationIssueView(issue: issue) } }
            if let message = model.routineConfirmation { Section { HydrationConfirmationView(message: message) } }
            Section {
                Button { Task { await model.saveRoutine() } } label: {
                    Text("Save reminder routine").frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent).tint(HydrationTheme.buttonTint)
                .foregroundStyle(.white)
                .accessibilityIdentifier("saveReminderRoutineButton")
                if model.isSavingRoutine || model.isRefreshingReminders { ProgressView("Updating water-break reminders…") }
                Button("Send test reminder") { Task { await model.sendReminderPreview() } }
                    .frame(minHeight: 44)
                    .disabled(model.notificationPermission != .authorized)
                    .accessibilityIdentifier("sendReminderPreviewButton")
                Button("Turn off reminders") { Task { await model.stopReminders() } }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("stopRemindersButton")
            } footer: {
                Text("Changes apply when you save. Up to 60 reminders are scheduled over the next 7 calendar days. Open the app regularly to keep the queue filled. Reaching today's goal pauses the rest of today's reminders.")
                    .foregroundStyle(HydrationTheme.supportingText)
            }
        }
        .navigationTitle("Routine")
        .disabled(model.isSaving || model.isSavingRoutine || model.isRefreshingReminders)
        .task { await model.refreshReminderSchedule() }
        .onChange(of: model.routineStart) { model.clearRoutineFeedback() }
        .onChange(of: model.routineEnd) { model.clearRoutineFeedback() }
        .onChange(of: model.routineInterval) { model.clearRoutineFeedback() }
    }
}
