import SwiftUI

struct HydrationTodayView: View {
    @Environment(HydrationWorkspaceViewModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(model.today, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline).foregroundStyle(HydrationTheme.supportingText)
                if let issue = model.todayIssue {
                    HydrationCard {
                        HydrationIssueView(issue: issue)
                        Button("Reload today's intake") { Task { await model.refreshToday() } }
                            .padding(.top, 8)
                    }
                }
                if let progress = model.todayProgress {
                    HydrationProgressCard(progress: progress)
                    Button { model.openIntakeForm() } label: {
                        Label("Record water", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent).tint(HydrationTheme.buttonTint)
                    .foregroundStyle(.white)
                    .disabled(model.isSaving)
                    .accessibilityIdentifier("recordWaterButton")
                    HydrationQuickAddView()
                    if let message = model.todayConfirmation { HydrationConfirmationView(message: message) }
                    HydrationRecentIntakesView(entries: model.todayEntries)
                } else if model.isLoadingToday {
                    ProgressView("Loading today's water intake…").frame(maxWidth: .infinity, minHeight: 180)
                } else if model.todayIssue == nil {
                    HydrationCard {
                        ContentUnavailableView {
                            Label("Start with a daily goal", systemImage: "target")
                        } description: {
                            Text("Choose your target, then record water as you drink throughout the day.")
                        } actions: {
                            Button("Set today's goal") { model.selectGoalDay(model.today) }
                                .buttonStyle(.borderedProminent).tint(HydrationTheme.buttonTint)
                                .foregroundStyle(.white)
                                .controlSize(.large)
                        }
                    }
                }
            }
            .frame(maxWidth: 680)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(HydrationTheme.background)
        .navigationTitle("Today")
        .refreshable { await model.refreshToday() }
        .task { await model.refreshToday() }
        .sensoryFeedback(.success, trigger: model.lastSavedIntakeID)
    }
}

private struct HydrationQuickAddView: View {
    @Environment(HydrationWorkspaceViewModel.self) private var model
    @ScaledMetric(relativeTo: .body) private var choiceWidth: CGFloat = 100

    var body: some View {
        HydrationCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick add").font(.headline)
                Text("Tap after you've had water.").font(.callout).foregroundStyle(HydrationTheme.supportingText)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: min(choiceWidth, 280)))], spacing: 12) {
                    ForEach([150, 250, 500], id: \.self) { amount in
                        Button { Task { await model.quickAdd(amount) } } label: {
                            Text("\(amount) mL").frame(maxWidth: .infinity, minHeight: 36)
                        }
                            .buttonStyle(.bordered)
                            .disabled(model.isSaving)
                            .accessibilityLabel("Record \(amount) millilitres of water now")
                    }
                }
                if model.isSaving { ProgressView("Saving water intake…") }
            }
        }
    }
}

private struct HydrationRecentIntakesView: View {
    @Environment(HydrationWorkspaceViewModel.self) private var model
    let entries: [WaterIntakeEntry]

    var body: some View {
        HydrationCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent water intake").font(.headline)
                    Spacer()
                    Button("History") { model.historyDate = model.today; model.selectedTab = .history }
                        .frame(minHeight: 44)
                }
                if entries.isEmpty {
                    Text("No water recorded yet. Add your first drink when you're ready.")
                        .foregroundStyle(HydrationTheme.supportingText)
                } else {
                    ForEach(entries.prefix(3)) { entry in HydrationIntakeRow(entry: entry) }
                }
            }
        }
    }
}
