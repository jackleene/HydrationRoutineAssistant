import Foundation
import Testing
@testable import HydrationRoutineAssistant

@MainActor
struct HydrationWorkspaceViewModelTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func workspace(
        repository: any HydrationRepository = MockHydrationRepository(),
        store: WorkspaceRoutineStore? = nil
    ) -> HydrationWorkspaceViewModel {
        HydrationWorkspaceViewModel(repository: repository, routineStore: store ?? WorkspaceRoutineStore(), calendar: calendar)
    }

    @Test("Today shows saved progress and sorts intake records newest first")
    func todayLoadsProgressAndRecords() async throws {
        let date = Date()
        let goal = try HydrationGoal(date: date, targetMillilitres: 2_000)
        let earlier = try WaterIntakeEntry(
            goalID: goal.id, amountMillilitres: 250,
            recordedAt: calendar.startOfDay(for: date), now: date
        )
        let later = try WaterIntakeEntry(goalID: goal.id, amountMillilitres: 500, recordedAt: date, now: date)
        let model = workspace(repository: MockHydrationRepository(goal: goal, entries: [earlier, later]))

        await model.refreshToday()

        #expect(model.todayProgress?.consumedMillilitres == 750)
        #expect(model.todayProgress?.remainingMillilitres == 1_250)
        #expect(model.todayEntries == [later, earlier])
        #expect(model.todayIssue == nil)
        #expect(!model.isLoadingToday)
    }

    @Test("Today without a goal is an empty state, not a loading error")
    func missingTodayGoalIsEmpty() async {
        let repository = MockHydrationRepository()
        let model = workspace(repository: repository)

        await model.refreshToday()

        #expect(model.todayProgress == nil)
        #expect(model.todayEntries.isEmpty)
        #expect(model.todayIssue == nil)
        #expect(!model.isLoadingToday)
        #expect(await repository.intakeQueries.isEmpty)
    }

    @Test("Failed Today loads expose feedback and reset the loading flag")
    func todayLoadFailureShowsFeedback() async {
        let model = workspace(repository: MockHydrationRepository(failingOperation: .fetchGoal))

        await model.refreshToday()

        #expect(model.todayIssue != nil)
        #expect(model.todayProgress == nil)
        #expect(model.todayEntries.isEmpty)
        #expect(!model.isLoadingToday)
    }

    @Test("Failed history loads expose feedback and reset the loading flag")
    func historyLoadFailureShowsFeedback() async {
        let model = workspace(repository: MockHydrationRepository(failingOperation: .fetchGoal))

        await model.loadHistory()

        #expect(model.historyIssue == HydrationIssue(FetchHydrationHistoryUseCase.Failure.unableToLoadHistory))
        #expect(model.history == nil)
        #expect(!model.isLoadingHistory)
    }

    @Test("Failed goal loads retain the editable target and reset the loading flag")
    func goalLoadFailureRetainsInput() async {
        let model = workspace(repository: MockHydrationRepository(failingOperation: .fetchGoal))
        model.goalTargetText = "2500"

        await model.loadGoal()

        #expect(model.goalIssue != nil)
        #expect(model.goalTargetText == "2500")
        #expect(!model.isLoadingGoal)
    }

    @Test("Goal editing loads the saved target or the default for an empty day", arguments: [
        (target: Optional<Int>.none, text: "2000"), (target: 2_500, text: "2500")
    ])
    func goalLoadsTarget(_ input: (target: Int?, text: String)) async throws {
        let date = Date()
        let goal = try input.target.map { try HydrationGoal(date: date, targetMillilitres: $0) }
        let model = workspace(repository: MockHydrationRepository(goal: goal))
        model.goalDate = date

        await model.loadGoal()

        #expect(model.goalTargetText == input.text)
        #expect(model.goalIssue == nil)
        #expect(!model.isLoadingGoal)
    }

    @Test("Invalid goal input stays editable without saving", arguments: ["abc", "499", "5001"])
    func invalidGoalDoesNotSave(_ input: String) async {
        let repository = MockHydrationRepository()
        let model = workspace(repository: repository)
        model.goalTargetText = input

        let saved = await model.saveGoal()

        #expect(!saved)
        #expect(model.goalTargetText == input)
        #expect(model.goalIssue != nil)
        #expect(model.goalConfirmation == nil)
        #expect(!model.isSaving)
        #expect(await repository.savedGoals.isEmpty)
        model.goalTargetText = "2000"
        #expect(model.goalIssue == nil)
    }

    @Test("Saving a goal preserves its identity and refreshes Today and selected history")
    func goalSaveRefreshesPages() async throws {
        let date = Date()
        let goal = try HydrationGoal(date: date, targetMillilitres: 2_000)
        let repository = MockHydrationRepository(goal: goal)
        let model = workspace(repository: repository)
        model.goalDate = date
        model.historyDate = date
        model.goalTargetText = " 2500\n"

        let saved = await model.saveGoal()
        let stored = try #require(await repository.savedGoals.first)

        #expect(saved)
        #expect(stored.id == goal.id)
        #expect(stored.targetMillilitres == 2_500)
        #expect(model.todayProgress?.goal.targetMillilitres == 2_500)
        #expect(model.history?.progress?.goal.targetMillilitres == 2_500)
        #expect(model.goalConfirmation == "Daily goal saved.")
        #expect(!model.isSaving)
    }

    @Test("Opening the intake form resets old feedback and uses the selected day")
    func intakeFormResetsForSelectedDay() async {
        let model = workspace()
        model.intakeAmountText = "abc"
        _ = await model.saveIntake()
        #expect(model.intakeIssue != nil)
        let selected = calendar.date(byAdding: .day, value: -1, to: Date())!

        model.openIntakeForm(on: selected)

        #expect(model.sheet == .logWater)
        #expect(model.drinkingDate == selected)
        #expect(model.intakeAmountText == "250")
        #expect(model.intakeIssue == nil)
        #expect(!model.intakeNeedsGoal)
    }

    @Test("Invalid intake input is retained without saving", arguments: ["abc", "0", "1001"])
    func invalidIntakeDoesNotSave(_ input: String) async {
        let repository = MockHydrationRepository()
        let model = workspace(repository: repository)
        model.intakeAmountText = input

        let saved = await model.saveIntake()

        #expect(!saved)
        #expect(model.intakeAmountText == input)
        #expect(model.intakeIssue != nil)
        #expect(!model.intakeNeedsGoal)
        #expect(model.lastSavedIntakeID == nil)
        #expect(!model.isSaving)
        #expect(await repository.savedIntakes.isEmpty)
    }

    @Test("Missing goals show a goal action in the form and feedback on quick add")
    func missingIntakeGoalRoutesFeedback() async {
        let model = workspace()

        let saved = await model.saveIntake()

        #expect(!saved)
        #expect(model.intakeNeedsGoal)
        #expect(model.intakeIssue == HydrationIssue(LogWaterIntakeUseCase.Failure.missingDailyGoal))
        model.selectGoalDay(model.drinkingDate)
        #expect(model.selectedTab == .goal)
        #expect(model.goalDate == model.drinkingDate)

        await model.quickAdd(250)

        #expect(model.todayIssue == HydrationIssue(LogWaterIntakeUseCase.Failure.missingDailyGoal))
        #expect(model.intakeIssue == nil)
        #expect(!model.isSaving)
    }

    @Test("Form save and quick add refresh totals, records and selected history")
    func intakeSaveRefreshesPages() async throws {
        let date = Date()
        let goal = try HydrationGoal(date: date, targetMillilitres: 2_000)
        let repository = MockHydrationRepository(goal: goal)
        let model = workspace(repository: repository)
        model.historyDate = date
        model.drinkingDate = date
        model.intakeAmountText = " 250 "

        let saved = await model.saveIntake()
        let firstID = try #require(model.lastSavedIntakeID)

        #expect(saved)
        #expect(model.todayProgress?.consumedMillilitres == 250)
        #expect(model.history?.entries.count == 1)
        #expect(model.todayConfirmation == "250 mL recorded.")

        await model.quickAdd(500)

        #expect(model.todayProgress?.consumedMillilitres == 750)
        #expect(model.todayEntries.count == 2)
        #expect(model.history?.progress?.consumedMillilitres == 750)
        #expect(model.lastSavedIntakeID != firstID)
        #expect(model.todayConfirmation == "500 mL recorded.")
        #expect(await repository.savedIntakes.count == 2)
        #expect(!model.isSaving)
    }

    @Test("A failed intake write retains input and never announces success")
    func intakeWriteFailureRetainsInput() async throws {
        let goal = try HydrationGoal(date: Date(), targetMillilitres: 2_000)
        let repository = MockHydrationRepository(goal: goal, failingOperation: .saveIntake)
        let model = workspace(repository: repository)
        model.intakeAmountText = "500"

        let saved = await model.saveIntake()

        #expect(!saved)
        #expect(model.intakeAmountText == "500")
        #expect(model.intakeIssue != nil)
        #expect(!model.intakeNeedsGoal)
        #expect(model.todayConfirmation == nil)
        #expect(model.lastSavedIntakeID == nil)
        #expect(await repository.savedIntakes.isEmpty)
        #expect(!model.isSaving)
    }

    @Test("History moves by calendar day and cannot move beyond today")
    func historyNavigationStopsAtToday() async {
        let model = workspace()
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        model.historyDate = today

        model.moveHistoryDay(by: 1)
        #expect(model.historyDate == today)
        model.moveHistoryDay(by: -1)
        #expect(model.historyDate == yesterday)
        await model.loadHistory()
        #expect(model.history?.date == yesterday)
        #expect(model.history?.entries.isEmpty == true)
        model.moveHistoryDay(by: 1)
        #expect(model.historyDate == today)
    }

    @Test("A delayed history request cannot replace the newer selected day")
    func latestHistoryRequestWins() async {
        let repository = PausedHydrationRepository(base: MockHydrationRepository())
        let model = workspace(repository: repository)
        let olderDate = calendar.date(byAdding: .day, value: -2, to: Date())!
        let newerDate = calendar.date(byAdding: .day, value: 1, to: olderDate)!
        model.historyDate = olderDate
        let earlierRequest = Task { await model.loadHistory() }
        await repository.waitUntilPaused()
        #expect(model.isLoadingHistory)

        model.historyDate = newerDate
        await model.loadHistory()
        #expect(model.history?.date == newerDate)
        #expect(!model.isLoadingHistory)
        await repository.resume()
        await earlierRequest.value

        #expect(model.history?.date == newerDate)
        #expect(model.historyIssue == nil)
        #expect(!model.isLoadingHistory)
    }

    @Test("A second save is rejected while a goal write is in progress")
    func concurrentSaveDoesNotWriteTwice() async {
        let base = MockHydrationRepository()
        let repository = PausedHydrationRepository(base: base)
        let model = workspace(repository: repository)
        let firstSave = Task { await model.saveGoal() }
        await repository.waitUntilPaused()
        #expect(model.isSaving)

        let secondSaved = await model.saveGoal()
        #expect(!secondSaved)
        #expect(await base.savedGoals.isEmpty)
        await repository.resume()
        let firstSaved = await firstSave.value

        #expect(firstSaved)
        #expect(await base.savedGoals.count == 1)
        #expect(!model.isSaving)
    }

    @Test("Reminder preferences load into the form and save edited values")
    func routineLoadsAndSaves() async throws {
        let store = WorkspaceRoutineStore()
        store.saved = HydrationReminderRoutine(
            isEnabled: true, startMinute: 480, endMinute: 1_080, intervalMinutes: 90, weekdays: [2, 4]
        )
        let model = workspace(store: store)
        #expect(model.routineEnabled)
        #expect(calendar.component(.hour, from: model.routineStart) == 8)
        #expect(calendar.component(.hour, from: model.routineEnd) == 18)
        #expect(model.routineInterval == 90)
        #expect(model.routineWeekdays == [2, 4])
        model.toggleWeekday(.friday)
        model.routineInterval = 75

        await model.saveRoutine()

        let routine = try #require(store.saved)
        #expect(routine.isEnabled)
        #expect(routine.startMinute == 480)
        #expect(routine.endMinute == 1_080)
        #expect(routine.intervalMinutes == 75)
        #expect(routine.weekdays == [2, 4, 6])
        #expect(store.saveCount == 1)
        #expect(model.routineConfirmation == "Reminder routine saved.")
        #expect(model.routineIssue == nil)
    }

    @Test("Invalid reminder preferences do not overwrite the saved routine")
    func invalidRoutineRetainsSavedPreferences() async {
        let store = WorkspaceRoutineStore()
        store.saved = .initial
        let model = workspace(store: store)
        model.routineWeekdays = []

        await model.saveRoutine()

        #expect(store.saved == .initial)
        #expect(store.saveCount == 0)
        #expect(model.routineIssue == HydrationIssue(SaveHydrationReminderRoutineUseCase.Failure.missingWeekdays))
        #expect(model.routineConfirmation == nil)
        model.toggleWeekday(.monday)
        #expect(model.routineIssue == nil)
    }

    @Test("Preference storage failures show feedback instead of success")
    func routineStorageFailuresShowFeedback() async {
        let store = WorkspaceRoutineStore()
        store.loadFailure = .unreadablePreferences
        let model = workspace(store: store)
        #expect(model.routineIssue == HydrationIssue(HydrationRoutineStoreError.unreadablePreferences))
        #expect(!model.routineEnabled)
        #expect(model.routineInterval == 60)
        store.saveFailure = .saveFailed

        await model.saveRoutine()

        #expect(model.routineIssue == HydrationIssue(SaveHydrationReminderRoutineUseCase.Failure.unableToSaveRoutine))
        #expect(model.routineConfirmation == nil)
        #expect(store.saveCount == 0)
        model.clearRoutineFeedback()
        #expect(model.routineIssue == nil)
    }
}

@MainActor
private final class WorkspaceRoutineStore: HydrationReminderRoutineStore {
    var saved: HydrationReminderRoutine?
    var loadFailure: HydrationRoutineStoreError?
    var saveFailure: HydrationRoutineStoreError?
    private(set) var saveCount = 0

    func load() throws -> HydrationReminderRoutine? {
        if let loadFailure { throw loadFailure }
        return saved
    }

    func save(_ routine: HydrationReminderRoutine) throws {
        if let saveFailure { throw saveFailure }
        saved = routine
        saveCount += 1
    }
}

private actor PausedHydrationRepository: HydrationRepository {
    private let base: any HydrationRepository
    private var shouldPause = true
    private var pausedCall: CheckedContinuation<Void, Never>?
    private var pauseObserver: CheckedContinuation<Void, Never>?

    init(base: any HydrationRepository) { self.base = base }

    func fetchGoal(on date: Date) async throws -> HydrationGoal? {
        if shouldPause {
            shouldPause = false
            await withCheckedContinuation { continuation in
                pausedCall = continuation
                pauseObserver?.resume()
                pauseObserver = nil
            }
        }
        return try await base.fetchGoal(on: date)
    }

    func waitUntilPaused() async {
        if pausedCall != nil { return }
        await withCheckedContinuation { pauseObserver = $0 }
    }

    func resume() {
        pausedCall?.resume()
        pausedCall = nil
    }

    func saveGoal(_ goal: HydrationGoal) async throws { try await base.saveGoal(goal) }
    func fetchIntakes(for goalID: UUID, on date: Date) async throws -> [WaterIntakeEntry] {
        try await base.fetchIntakes(for: goalID, on: date)
    }
    func saveIntake(_ entry: WaterIntakeEntry) async throws { try await base.saveIntake(entry) }
}
