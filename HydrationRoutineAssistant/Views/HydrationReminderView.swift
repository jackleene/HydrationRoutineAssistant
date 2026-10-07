import SwiftUI

struct HydrationReminderView: View {
    @Environment(HydrationWorkspaceViewModel.self) private var model
    @ScaledMetric(relativeTo: .body) private var choiceWidth: CGFloat = 90

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Use this reminder routine", isOn: $model.routineEnabled)
                Text("Plan your water breaks. Notifications are not scheduled yet.")
                    .font(.callout).foregroundStyle(HydrationTheme.supportingText)
            } header: { Text("Your routine").foregroundStyle(HydrationTheme.supportingText) }
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
                Button(action: model.saveRoutine) {
                    Text("Save reminder routine").frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent).tint(HydrationTheme.buttonTint)
                .foregroundStyle(.white)
                .accessibilityIdentifier("saveReminderRoutineButton")
            } footer: {
                Text("Preferences are saved on this device. Notifications are not scheduled yet.")
                    .foregroundStyle(HydrationTheme.supportingText)
            }
        }
        .navigationTitle("Routine")
        .onChange(of: model.routineEnabled) { model.clearRoutineFeedback() }
        .onChange(of: model.routineStart) { model.clearRoutineFeedback() }
        .onChange(of: model.routineEnd) { model.clearRoutineFeedback() }
        .onChange(of: model.routineInterval) { model.clearRoutineFeedback() }
    }
}
