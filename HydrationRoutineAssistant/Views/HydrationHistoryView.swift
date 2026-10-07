import SwiftUI

struct HydrationHistoryView: View {
    @Environment(HydrationWorkspaceViewModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                DatePicker("History date", selection: $model.historyDate, in: ...Date(), displayedComponents: .date)
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        Button("Previous day") { model.moveHistoryDay(by: -1) }.frame(minHeight: 44)
                        Button("Next day") { model.moveHistoryDay(by: 1) }
                            .disabled(model.calendar.isDateInToday(model.historyDate)).frame(minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                } else {
                    HStack {
                        Button { model.moveHistoryDay(by: -1) } label: { Label("Previous", systemImage: "chevron.left") }
                        Spacer()
                        Button { model.moveHistoryDay(by: 1) } label: { Label("Next", systemImage: "chevron.right") }
                            .disabled(model.calendar.isDateInToday(model.historyDate))
                    }
                    .buttonStyle(.borderless).frame(minHeight: 44)
                }
            } header: { Text("Choose a day").foregroundStyle(HydrationTheme.supportingText) }
            if let issue = model.historyIssue {
                Section {
                    HydrationIssueView(issue: issue)
                    Button("Reload this day") { Task { await model.loadHistory() } }
                }
            } else if model.isLoadingHistory {
                Section { ProgressView("Loading water intake history…") }
            } else if let history = model.history {
                if let progress = history.progress {
                    Section {
                        HydrationMetricView(title: "Recorded", millilitres: progress.consumedMillilitres)
                        HydrationMetricView(title: "Daily goal", millilitres: progress.goal.targetMillilitres)
                        ProgressView(value: progress.completionFraction)
                            .accessibilityLabel("Daily goal progress")
                            .accessibilityValue(progress.completionFraction.formatted(.percent))
                    } header: { Text("Day summary").foregroundStyle(HydrationTheme.supportingText) }
                    Section {
                        if history.entries.isEmpty {
                            ContentUnavailableView("No water recorded", systemImage: "drop",
                                                   description: Text("Water you record for this day will appear here."))
                        } else {
                            ForEach(history.entries) { HydrationIntakeRow(entry: $0) }
                        }
                    } header: { Text("Water intake records").foregroundStyle(HydrationTheme.supportingText) }
                } else {
                    Section {
                        ContentUnavailableView {
                            Label("No daily goal for this day", systemImage: "calendar")
                        } description: {
                            Text("Set a goal to start tracking water intake for the selected day.")
                        } actions: {
                            Button("Set this day's goal") { model.selectGoalDay(model.historyDate) }
                                .frame(minHeight: 44)
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let date = model.calendar.isDateInToday(model.historyDate) ? Date() :
                        (model.calendar.date(bySettingHour: 12, minute: 0, second: 0, of: model.historyDate) ?? model.historyDate)
                    model.openIntakeForm(on: date)
                } label: { Label("Record water for this day", systemImage: "plus") }
                .disabled(model.history?.progress == nil || model.isLoadingHistory || model.isSaving)
            }
        }
        .refreshable { await model.loadHistory() }
        .task(id: model.calendar.startOfDay(for: model.historyDate)) { await model.loadHistory() }
    }
}
