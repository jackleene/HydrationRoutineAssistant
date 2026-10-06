import Foundation
import Testing
@testable import HydrationRoutineAssistant

struct CoreDataHydrationRepositoryTests {
    private let now = Date(timeIntervalSince1970: 1_791_331_200)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 10 * 60 * 60)!
        return calendar
    }

    @Test("Daily goals and intake edits survive reopening the hydration store")
    func savedHydrationSurvivesReopening() async throws {
        let url = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = try await makeRepository(storeURL: url)
        let goal = try HydrationGoal(date: now, targetMillilitres: 2_000)
        try await repository.saveGoal(goal)
        let entry = try WaterIntakeEntry(
            goalID: goal.id, amountMillilitres: 250, recordedAt: now, now: now
        )
        try await repository.saveIntake(entry)
        let updatedGoal = try HydrationGoal(id: goal.id, date: now, targetMillilitres: 2_250)
        let updatedEntry = try WaterIntakeEntry(
            id: entry.id, goalID: goal.id, amountMillilitres: 300, recordedAt: now, now: now
        )
        try await repository.saveGoal(updatedGoal)
        try await repository.saveIntake(updatedEntry)

        let reopenedRepository = try await makeRepository(storeURL: url)
        #expect(try await reopenedRepository.fetchGoal(on: now) == updatedGoal)
        #expect(try await reopenedRepository.fetchIntakes(for: goal.id, on: now) == [updatedEntry])
    }

    @Test("Daily intake queries include midnight and exclude other goals and days")
    func intakeQueriesUseGoalAndDay() async throws {
        let url = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = try await makeRepository(storeURL: url)
        let day = try #require(calendar.dateInterval(of: .day, for: now))
        let goal = try HydrationGoal(date: now, targetMillilitres: 2_000)
        let tomorrowGoal = try HydrationGoal(date: day.end, targetMillilitres: 2_000)
        try await repository.saveGoal(goal)
        try await repository.saveGoal(tomorrowGoal)

        let first = try WaterIntakeEntry(
            goalID: goal.id, amountMillilitres: 100, recordedAt: day.start, now: day.end
        )
        let last = try WaterIntakeEntry(
            goalID: goal.id, amountMillilitres: 200,
            recordedAt: day.end.addingTimeInterval(-1), now: day.end
        )
        let tomorrow = try WaterIntakeEntry(
            goalID: tomorrowGoal.id, amountMillilitres: 400, recordedAt: day.end, now: day.end
        )
        for entry in [last, tomorrow, first] {
            try await repository.saveIntake(entry)
        }

        #expect(try await repository.fetchIntakes(for: goal.id, on: now) == [first, last])
        #expect(try await repository.fetchIntakes(for: tomorrowGoal.id, on: now).isEmpty)
        #expect(try await repository.fetchIntakes(for: goal.id, on: day.end).isEmpty)
        #expect(try await repository.fetchIntakes(for: tomorrowGoal.id, on: day.end) == [tomorrow])
        #expect(try await repository.fetchGoal(on: day.start) == goal)
        #expect(try await repository.fetchGoal(on: day.end) == tomorrowGoal)
        #expect(try await repository.fetchGoal(on: day.start.addingTimeInterval(-1)) == nil)
    }

    @Test("A second daily goal is rejected without changing the saved goal")
    func duplicateDailyGoalIsRejected() async throws {
        let url = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = try await makeRepository(storeURL: url)
        let goal = try HydrationGoal(date: now, targetMillilitres: 2_000)
        let duplicate = try HydrationGoal(date: now.addingTimeInterval(1), targetMillilitres: 2_500)
        try await repository.saveGoal(goal)

        await #expect(throws: HydrationRepositoryError.duplicateDailyGoal) {
            try await repository.saveGoal(duplicate)
        }
        #expect(try await repository.fetchGoal(on: now) == goal)
    }

    @Test("Intake records require a saved goal for their drinking day", arguments: InvalidIntakeScenario.allCases)
    func invalidIntakeDoesNotLeaveSavedChanges(_ scenario: InvalidIntakeScenario) async throws {
        let url = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = try await makeRepository(storeURL: url)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let goal = try HydrationGoal(date: yesterday, targetMillilitres: 2_000)
        if scenario == .otherDay {
            try await repository.saveGoal(goal)
        }
        let entry = try WaterIntakeEntry(
            goalID: goal.id, amountMillilitres: 250, recordedAt: now, now: now
        )
        let expectedError: HydrationRepositoryError = scenario == .missingGoal ? .missingGoal : .goalDayMismatch

        await #expect(throws: expectedError) {
            try await repository.saveIntake(entry)
        }
        #expect(try await repository.fetchIntakes(for: goal.id, on: now).isEmpty)
    }

    enum InvalidIntakeScenario: CaseIterable, Sendable {
        case missingGoal
        case otherDay
    }

    private func makeStoreURL() -> URL {
        // Isolate SQLite files so parallel tests cannot alter each other's hydration history.
        FileManager.default.temporaryDirectory
            .appendingPathComponent("hydration-repository-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("HydrationModel.sqlite")
    }

    private func makeRepository(storeURL: URL) async throws -> CoreDataHydrationRepository {
        let container = try await HydrationPersistence.makeContainer(storeURL: storeURL)
        return CoreDataHydrationRepository(container: container, calendar: calendar)
    }
}
