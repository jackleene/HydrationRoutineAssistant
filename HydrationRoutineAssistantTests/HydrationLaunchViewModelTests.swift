import Testing
@testable import HydrationRoutineAssistant

@MainActor
struct HydrationLaunchViewModelTests {
    @Test("Successful launch loads the workspace only once")
    func workspaceLoadsOnce() async {
        let workspace = HydrationWorkspaceViewModel(
            repository: MockHydrationRepository(), routineStore: LaunchRoutineStore()
        )
        var loadCount = 0
        let model = HydrationLaunchViewModel {
            loadCount += 1
            return workspace
        }

        await model.open()
        await model.open()

        #expect(model.workspace === workspace)
        #expect(loadCount == 1)
        #expect(model.issue == nil)
        #expect(!model.isLoading)
    }

    @Test("Failed launch exposes recovery feedback and permits a successful retry")
    func launchCanRetry() async {
        let workspace = HydrationWorkspaceViewModel(
            repository: MockHydrationRepository(), routineStore: LaunchRoutineStore()
        )
        var loadCount = 0
        let model = HydrationLaunchViewModel {
            loadCount += 1
            if loadCount == 1 { throw HydrationRepositoryError.storageUnavailable }
            return workspace
        }

        await model.open()

        #expect(model.workspace == nil)
        #expect(model.issue == HydrationIssue(HydrationRepositoryError.storageUnavailable))
        #expect(model.issue?.recovery != nil)
        #expect(!model.isLoading)

        await model.open()

        #expect(model.workspace === workspace)
        #expect(loadCount == 2)
        #expect(model.issue == nil)
        #expect(!model.isLoading)
    }
}

@MainActor
private final class LaunchRoutineStore: HydrationReminderRoutineStore {
    func load() throws -> HydrationReminderRoutine? { nil }
    func save(_ routine: HydrationReminderRoutine) throws {}
}
