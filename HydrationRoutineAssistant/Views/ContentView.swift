import SwiftUI

struct ContentView: View {
    let launcher: HydrationLaunchViewModel

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
                }
            }
        }
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
