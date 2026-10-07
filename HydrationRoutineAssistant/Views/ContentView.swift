import SwiftUI

struct ContentView: View {
    let launcher: HydrationLaunchViewModel
    @State private var pendingTodayLink = false

    var body: some View {
        Group {
            if let workspace = launcher.workspace {
                HydrationWorkspaceView(model: workspace)
            } else if let issue = launcher.issue {
                ContentUnavailableView {
                    Label("Hydration history is unavailable", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(issue.message)
                    if let recovery = issue.recovery { Text(recovery) }
                } actions: {
                    Button("Try again") { Task { await launcher.open() } }
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(.white)
                        .controlSize(.large)
                        .tint(HydrationTheme.buttonTint)
                }
            } else {
                ProgressView("Opening your hydration history…")
            }
        }
        .task { await launcher.open() }
        .onOpenURL { url in
            guard HydrationWidgetIdentity.opensToday(url) else { return }
            pendingTodayLink = true
            openTodayFromWidget()
        }
        .onChange(of: launcher.workspace != nil) { openTodayFromWidget() }
    }

    private func openTodayFromWidget() {
        guard pendingTodayLink, let workspace = launcher.workspace else { return }
        pendingTodayLink = false
        workspace.selectedTab = .today
        workspace.sheet = nil
        Task { await workspace.refreshToday() }
    }
}

struct HydrationWorkspaceView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var model: HydrationWorkspaceViewModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            Tab("Today", systemImage: "drop", value: HydrationWorkspaceViewModel.Tab.today) {
                NavigationStack { HydrationTodayView() }
            }
            Tab("History", systemImage: "clock", value: HydrationWorkspaceViewModel.Tab.history) {
                NavigationStack { HydrationHistoryView() }
            }
            Tab("Goal", systemImage: "target", value: HydrationWorkspaceViewModel.Tab.goal) {
                NavigationStack { HydrationDailyGoalView() }
            }
            Tab("Routine", systemImage: "bell", value: HydrationWorkspaceViewModel.Tab.routine) {
                NavigationStack { HydrationReminderView() }
            }
        }
        .environment(model)
        .tint(HydrationTheme.accent)
        .sheet(item: $model.sheet) { _ in
            NavigationStack { HydrationLogWaterView() }
                .environment(model)
                .interactiveDismissDisabled(model.isSaving)
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task {
                    await model.refreshToday()
                    await model.loadHistory()
                    await model.refreshReminderSchedule()
                }
            }
        }
        .task { await model.refreshReminderSchedule() }
    }
}

#if DEBUG
#Preview("Hydration workflow") {
    ContentView(launcher: HydrationLaunchViewModel(loader: {
        HydrationWorkspaceViewModel(
            repository: HydrationPreviewRepository(), routineStore: HydrationPreviewRoutineStore()
        )
    }))
}
#endif
