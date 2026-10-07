import SwiftUI

struct HydrationLogWaterView: View {
    @Environment(HydrationWorkspaceViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @FocusState private var amountFocused: Bool
    @ScaledMetric(relativeTo: .body) private var choiceWidth: CGFloat = 80

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                LabeledContent("Amount (mL)") {
                    TextField("250", text: $model.intakeAmountText)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        .focused($amountFocused).accessibilityLabel("Water amount in millilitres")
                        .accessibilityIdentifier("waterAmountField")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: min(choiceWidth, 280)))], spacing: 8) {
                    ForEach([150, 250, 500, 750], id: \.self) { amount in
                        Button { model.intakeAmountText = String(amount); amountFocused = false } label: {
                            Text("\(amount) mL").frame(maxWidth: .infinity, minHeight: 36)
                        }
                            .buttonStyle(.bordered)
                    }
                }
            } header: { Text("Water you drank").foregroundStyle(HydrationTheme.supportingText) }
              footer: {
                  Text("Record 1–1000 mL per entry. Larger drinks can be recorded as separate entries.")
                      .foregroundStyle(HydrationTheme.supportingText)
              }
            Section {
                DatePicker("When did you drink?", selection: $model.drinkingDate, in: ...Date())
            } header: { Text("Drinking time").foregroundStyle(HydrationTheme.supportingText) }
            if let issue = model.intakeIssue {
                Section {
                    HydrationIssueView(issue: issue)
                    if model.intakeNeedsGoal {
                        Button("Set a goal for this day") {
                            model.selectGoalDay(model.drinkingDate)
                            dismiss()
                        }
                    }
                }
            }
            Section {
                Button(action: save) {
                    if model.isSaving { ProgressView("Saving…").tint(.white).frame(maxWidth: .infinity) }
                    else { Text("Save water intake").frame(maxWidth: .infinity, minHeight: 36) }
                }
                .buttonStyle(.borderedProminent).tint(HydrationTheme.buttonTint)
                .foregroundStyle(.white)
                .accessibilityIdentifier("saveWaterIntakeButton")
            }
        }
        .disabled(model.isSaving)
        .navigationTitle("Record water")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.isSaving) }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { amountFocused = false }
            }
        }
    }

    private func save() {
        amountFocused = false
        Task { if await model.saveIntake() { dismiss() } }
    }
}
