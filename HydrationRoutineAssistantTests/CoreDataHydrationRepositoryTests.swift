import CoreData
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

    @Test("Intake records require a saved goal for their drinking day", arguments: [
        (InvalidIntakeScenario.missingGoal, HydrationRepositoryError.missingGoal),
        (.otherDay, .goalDayMismatch)
    ])
    func invalidIntakeDoesNotLeaveSavedChanges(
        _ scenario: InvalidIntakeScenario, expectedError: HydrationRepositoryError
    ) async throws {
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
        await #expect(throws: expectedError) {
            try await repository.saveIntake(entry)
        }
        #expect(try await repository.fetchIntakes(for: goal.id, on: now).isEmpty)
    }

    @Test("Daily hydration queries follow short and long daylight-saving days", arguments: [
        (month: 4, day: 5, hours: 25),
        (month: 10, day: 4, hours: 23)
    ])
    func queriesFollowDaylightSavingBoundaries(_ transition: (month: Int, day: Int, hours: Int)) async throws {
        let (month, day, hours) = transition
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = try #require(TimeZone(identifier: "Australia/Sydney"))
        let date = try #require(localCalendar.date(from: DateComponents(
            year: 2026, month: month, day: day, hour: 12
        )))
        let interval = try #require(localCalendar.dateInterval(of: .day, for: date))
        try #require(interval.duration == Double(hours * 3_600))
        let url = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = try await makeRepository(storeURL: url, calendar: localCalendar)
        let goal = try HydrationGoal(date: date, targetMillilitres: 2_000)
        let nextGoal = try HydrationGoal(date: interval.end, targetMillilitres: 2_500)
        try await repository.saveGoal(goal)
        try await repository.saveGoal(nextGoal)
        let finalIntake = try WaterIntakeEntry(
            goalID: goal.id, amountMillilitres: 250,
            recordedAt: interval.end.addingTimeInterval(-1), now: interval.end
        )
        try await repository.saveIntake(finalIntake)

        #expect(try await repository.fetchGoal(on: interval.start) == goal)
        #expect(try await repository.fetchGoal(on: interval.end.addingTimeInterval(-1)) == goal)
        #expect(try await repository.fetchGoal(on: interval.end) == nextGoal)
        #expect(try await repository.fetchIntakes(for: goal.id, on: date) == [finalIntake])
        #expect(try await repository.fetchIntakes(for: goal.id, on: interval.end).isEmpty)
    }

    @Test("An existing daily goal cannot move its intake history to another day")
    func changingGoalDayPreservesItsHistory() async throws {
        let url = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = try await makeRepository(storeURL: url)
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))
        let goal = try HydrationGoal(date: now, targetMillilitres: 2_000)
        let movedGoal = try HydrationGoal(id: goal.id, date: tomorrow, targetMillilitres: 2_500)
        let entry = try WaterIntakeEntry(
            goalID: goal.id, amountMillilitres: 250, recordedAt: now, now: now
        )
        try await repository.saveGoal(goal)
        try await repository.saveIntake(entry)

        await #expect(throws: HydrationRepositoryError.goalDayMismatch) {
            try await repository.saveGoal(movedGoal)
        }
        #expect(try await repository.fetchGoal(on: now) == goal)
        #expect(try await repository.fetchGoal(on: tomorrow) == nil)
        #expect(try await repository.fetchIntakes(for: goal.id, on: now) == [entry])
    }

    @Test("Failed hydration writes leave saved goals and intake history unchanged")
    func failedWritesRollBackHydrationChanges() async throws {
        let url = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = try await makeRepository(storeURL: url)
        let goal = try HydrationGoal(date: now, targetMillilitres: 2_000)
        let entry = try WaterIntakeEntry(
            goalID: goal.id, amountMillilitres: 250, recordedAt: now, now: now
        )
        try await repository.saveGoal(goal)
        try await repository.saveIntake(entry)

        let container = try await HydrationPersistence.makeContainer(storeURL: url)
        let coordinator = container.persistentStoreCoordinator
        let writableStore = try #require(coordinator.persistentStores.first)
        try coordinator.remove(writableStore)
        // A read-only store forces a real save failure without relying on disk space or permissions.
        let readOnlyStore = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType, configurationName: nil, at: url,
            options: [NSReadOnlyPersistentStoreOption: true]
        )
        try #require(readOnlyStore.isReadOnly)
        let readOnlyRepository = CoreDataHydrationRepository(container: container, calendar: calendar)
        let updatedGoal = try HydrationGoal(id: goal.id, date: now, targetMillilitres: 2_500)
        let anotherEntry = try WaterIntakeEntry(
            goalID: goal.id, amountMillilitres: 500, recordedAt: now, now: now
        )

        await #expect(throws: HydrationRepositoryError.saveFailed) {
            try await readOnlyRepository.saveGoal(updatedGoal)
        }
        #expect(try await readOnlyRepository.fetchGoal(on: now) == goal)
        await #expect(throws: HydrationRepositoryError.saveFailed) {
            try await readOnlyRepository.saveIntake(anotherEntry)
        }
        #expect(try await readOnlyRepository.fetchIntakes(for: goal.id, on: now) == [entry])
    }

    @Test("Ambiguous saved daily goals are reported instead of silently selected")
    func ambiguousGoalsAreReported() async throws {
        let url = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let container = try await HydrationPersistence.makeContainer(storeURL: url)
        let context = container.newBackgroundContext()
        let goal = try HydrationGoal(date: now, targetMillilitres: 2_000)
        try await context.perform {
            let description = try #require(NSEntityDescription.entity(
                forEntityName: "HydrationGoalEntity", in: context
            ))
            // Seed inconsistent data directly because repository saves reject duplicate goal identities.
            for target in [2_000, 2_500] {
                let entity = HydrationGoalEntity(entity: description, insertInto: context)
                entity.id = goal.id
                entity.date = goal.date
                entity.targetMillilitres = Int64(target)
            }
            try context.save()
        }
        let repository = CoreDataHydrationRepository(container: container, calendar: calendar)

        await #expect(throws: HydrationRepositoryError.invalidStoredData) {
            try await repository.fetchGoal(on: now)
        }
        await #expect(throws: HydrationRepositoryError.invalidStoredData) {
            try await repository.saveGoal(goal)
        }
        let count = try await context.perform {
            try context.count(for: HydrationGoalEntity.fetchRequest())
        }
        #expect(count == 2)
    }

    @Test("An unavailable hydration store reports a recoverable opening error")
    func unavailableStoreReportsOpeningError() async throws {
        let url = makeStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // A directory cannot be opened as a SQLite database file.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        await #expect(throws: HydrationRepositoryError.storageUnavailable) {
            try await HydrationPersistence.makeContainer(storeURL: url)
        }
    }

    enum InvalidIntakeScenario: Sendable {
        case missingGoal
        case otherDay
    }

    private func makeStoreURL() -> URL {
        // Isolate SQLite files so parallel tests cannot alter each other's hydration history.
        FileManager.default.temporaryDirectory
            .appendingPathComponent("hydration-repository-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("HydrationModel.sqlite")
    }

    private func makeRepository(
        storeURL: URL, calendar: Calendar? = nil
    ) async throws -> CoreDataHydrationRepository {
        let container = try await HydrationPersistence.makeContainer(storeURL: storeURL)
        return CoreDataHydrationRepository(container: container, calendar: calendar ?? self.calendar)
    }
}
