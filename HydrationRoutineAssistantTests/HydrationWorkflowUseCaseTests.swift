import Foundation
import Testing
@testable import HydrationRoutineAssistant

struct HydrationWorkflowUseCaseTests {
    private let date = Date(timeIntervalSince1970: 1_791_331_200)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test("Selected-day history includes only the matching goal's water intake")
    func historyFiltersUnrelatedIntakes() async throws {
        let goal = try HydrationGoal(date: date, targetMillilitres: 2_000)
        let entry = try WaterIntakeEntry(goalID: goal.id, amountMillilitres: 250, recordedAt: date, now: date)
        let unrelated = try WaterIntakeEntry(goalID: UUID(), amountMillilitres: 500, recordedAt: date, now: date)
        let repository = MockHydrationRepository(goal: goal, entries: [entry, unrelated])

        let history = try await FetchHydrationHistoryUseCase(repository: repository, calendar: calendar).execute(on: date)

        #expect(history.entries == [entry])
        #expect(history.progress?.consumedMillilitres == 250)
        #expect(await repository.intakeQueries == [.init(goalID: goal.id, date: date)])
    }

    @Test("A day with no hydration goal has empty history without an intake query")
    func absentGoalProducesEmptyHistory() async throws {
        let repository = MockHydrationRepository()
        let history = try await FetchHydrationHistoryUseCase(repository: repository, calendar: calendar).execute(on: date)
        #expect(history.progress == nil)
        #expect(history.entries.isEmpty)
        #expect(await repository.intakeQueries.isEmpty)
    }

    @Test("Valid reminder preferences are saved through their store")
    @MainActor
    func validRoutineIsSaved() throws {
        let store = MockHydrationReminderRoutineStore()
        let routine = HydrationReminderRoutine(
            isEnabled: true, startMinute: 540, endMinute: 1_020, intervalMinutes: 60, weekdays: [2, 3, 4, 5, 6]
        )
        try SaveHydrationReminderRoutineUseCase(store: store).execute(routine)
        #expect(store.saved == routine)
    }

    @Test("Invalid reminder windows, intervals and missing days never reach the store", arguments: [
        (end: 540, interval: 60, weekdays: Set([2]), failure: SaveHydrationReminderRoutineUseCase.Failure.invalidTimeWindow),
        (end: 1_020, interval: 14, weekdays: Set([2]), failure: .unsupportedInterval),
        (end: 1_020, interval: 60, weekdays: Set<Int>(), failure: .missingWeekdays)
    ])
    @MainActor
    func invalidRoutineDoesNotSave(
        _ input: (end: Int, interval: Int, weekdays: Set<Int>, failure: SaveHydrationReminderRoutineUseCase.Failure)
    ) {
        let store = MockHydrationReminderRoutineStore()
        let routine = HydrationReminderRoutine(
            isEnabled: true, startMinute: 540, endMinute: input.end,
            intervalMinutes: input.interval, weekdays: input.weekdays
        )
        #expect(throws: input.failure) { try SaveHydrationReminderRoutineUseCase(store: store).execute(routine) }
        #expect(store.saved == nil)
    }
}

@MainActor
private final class MockHydrationReminderRoutineStore: HydrationReminderRoutineStore {
    var saved: HydrationReminderRoutine?
    func load() throws -> HydrationReminderRoutine? { saved }
    func save(_ routine: HydrationReminderRoutine) throws { saved = routine }
}
