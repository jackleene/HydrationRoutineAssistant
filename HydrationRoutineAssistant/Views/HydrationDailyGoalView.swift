import SwiftUI

struct HydrationDailyGoalView: View {
    @Environment(HydrationWorkspaceViewModel.self) private var model
    @FocusState private var targetFocused: Bool
    @ScaledMetric(relativeTo: .body) private var choiceWidth: CGFloat = 100

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                DatePicker("Goal day", selection: $model.goalDate, in: ...Date(), displayedComponents: .date)
                LabeledContent("Target (mL)") {
                    TextField("2000", text: $model.goalTargetText)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        .focused($targetFocused).accessibilityLabel("Daily hydration target in millilitres")
                        .accessibilityIdentifier("dailyGoalTargetField")
                }
                .disabled(model.isLoadingGoal)
                if model.isLoadingGoal { ProgressView("Loading daily goal…") }
            } header: { Text("Daily hydration goal").foregroundStyle(HydrationTheme.supportingText) }
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: min(choiceWidth, 280)))], spacing: 8) {
                    ForEach([1_500, 2_000, 2_500], id: \.self) { target in
                        Button { model.goalTargetText = String(target); targetFocused = false } label: {
                            Text("\(target.formatted()) mL").frame(maxWidth: .infinity, minHeight: 36)
                        }
                            .buttonStyle(.bordered)
                    }
                }
                Text("Choose a target that fits your routine. Supported input: 500–5000 mL.")
                    .font(.callout).foregroundStyle(HydrationTheme.supportingText)
            } header: { Text("Target choices").foregroundStyle(HydrationTheme.supportingText) }
            if let issue = model.goalIssue { Section { HydrationIssueView(issue: issue) } }
            if let message = model.goalConfirmation { Section { HydrationConfirmationView(message: message) } }
            Section {
                Button(action: save) {
                    if model.isSaving { ProgressView("Saving…").tint(.white).frame(maxWidth: .infinity) }
                    else { Text("Save daily goal").frame(maxWidth: .infinity, minHeight: 36) }
                }
                .buttonStyle(.borderedProminent).tint(HydrationTheme.buttonTint)
                .foregroundStyle(.white)
                .disabled(model.isLoadingGoal)
                .accessibilityIdentifier("saveDailyGoalButton")
            } footer: {
                Text("Changing the target keeps the water intake records linked to this day.")
                    .foregroundStyle(HydrationTheme.supportingText)
            }
        }
        .disabled(model.isSaving)
        .navigationTitle("Daily goal")
        .task(id: model.calendar.startOfDay(for: model.goalDate)) { await model.loadGoal() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { targetFocused = false } }
        }
    }

    private func save() {
        targetFocused = false
        Task { _ = await model.saveGoal() }
    }
}
