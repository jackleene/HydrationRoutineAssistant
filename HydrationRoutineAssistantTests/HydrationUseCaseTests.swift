import Foundation
import Testing
@testable import HydrationRoutineAssistant

private enum HydrationUseCaseFixtures {
    static let now = Date(timeIntervalSince1970: 1_791_331_200)

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 10 * 60 * 60)!
        return calendar
    }
}

struct LogWaterIntakeUseCaseTests {
    @Test("Supported intake boundaries are saved against the drinking day's goal", arguments: [1, 1_000])
    func supportedIntakeIsSavedForDailyGoal(_ amount: Int) async throws {
        let date = HydrationUseCaseFixtures.now
        let drinkingTime = date.addingTimeInterval(-60)
        let goal = try HydrationGoal(date: date, targetMillilitres: 2_000)
        let repository = MockHydrationRepository(goal: goal)
        let useCase = LogWaterIntakeUseCase(
            repository: repository, calendar: HydrationUseCaseFixtures.calendar, now: { date }
        )

        let entry = try await useCase.execute(amountMillilitres: amount, recordedAt: drinkingTime)

        #expect(entry.goalID == goal.id)
        #expect(entry.amountMillilitres == amount)
        #expect(entry.recordedAt == drinkingTime)
        #expect(await repository.savedIntakes == [entry])
        #expect(await repository.requestedGoalDates == [drinkingTime])
    }

    @Test("Invalid intake amounts and future drinking times are rejected before using the repository", arguments: [
        (amount: 0, secondsAhead: 0, failure: LogWaterIntakeUseCase.Failure.amountOutsideSupportedRange),
        (amount: 1_001, secondsAhead: 0, failure: .amountOutsideSupportedRange),
        (amount: 250, secondsAhead: 1, failure: .recordedInFuture)
    ])
    func invalidInputDoesNotAccessRepository(
        _ input: (amount: Int, secondsAhead: Int, failure: LogWaterIntakeUseCase.Failure)
    ) async {
        let date = HydrationUseCaseFixtures.now
        let repository = MockHydrationRepository()
        let useCase = LogWaterIntakeUseCase(repository: repository, now: { date })

        await #expect(throws: input.failure) {
            try await useCase.execute(
                amountMillilitres: input.amount,
                recordedAt: date.addingTimeInterval(Double(input.secondsAhead))
            )
        }
        #expect(await repository.requestedGoalDates.isEmpty)
        #expect(await repository.savedIntakes.isEmpty)
    }

    @Test("Water intake cannot be recorded without a daily goal")
    func missingDailyGoalPreventsRecording() async {
        let date = HydrationUseCaseFixtures.now
        let repository = MockHydrationRepository()
        let useCase = LogWaterIntakeUseCase(repository: repository, now: { date })

        await #expect(throws: LogWaterIntakeUseCase.Failure.missingDailyGoal) {
            try await useCase.execute(amountMillilitres: 250, recordedAt: date)
        }
        #expect(await repository.savedIntakes.isEmpty)
    }

    @Test("Repository failures explain which part of recording water failed", arguments: [
        (MockHydrationRepository.Operation.fetchGoal, LogWaterIntakeUseCase.Failure.unableToLoadDailyGoal),
        (.saveIntake, .unableToSaveIntake)
    ])
    func recordingFailuresUseDomainErrors(
        _ operation: MockHydrationRepository.Operation, expectedFailure: LogWaterIntakeUseCase.Failure
    ) async throws {
        let date = HydrationUseCaseFixtures.now
        let goal = try HydrationGoal(date: date, targetMillilitres: 2_000)
        let repository = MockHydrationRepository(goal: goal, failingOperation: operation)
        let useCase = LogWaterIntakeUseCase(
            repository: repository, calendar: HydrationUseCaseFixtures.calendar, now: { date }
        )

        await #expect(throws: expectedFailure) {
            try await useCase.execute(amountMillilitres: 250, recordedAt: date)
        }
        #expect(await repository.savedIntakes.isEmpty)
        #expect(!(try #require(expectedFailure.recoverySuggestion)).isEmpty)
    }

    @Test("A goal from another day cannot receive the drinking day's water intake")
    func wrongDayGoalPreventsRecording() async throws {
        let date = HydrationUseCaseFixtures.now
        let calendar = HydrationUseCaseFixtures.calendar
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: date))
        let goal = try HydrationGoal(date: yesterday, targetMillilitres: 2_000)
        let repository = MockHydrationRepository(goal: goal)
        let useCase = LogWaterIntakeUseCase(repository: repository, calendar: calendar, now: { date })

        await #expect(throws: LogWaterIntakeUseCase.Failure.goalDayMismatch) {
            try await useCase.execute(amountMillilitres: 250, recordedAt: date)
        }
        #expect(await repository.savedIntakes.isEmpty)
    }

    @Test("Goal changes during recording produce actionable intake errors", arguments: [
        (HydrationRepositoryError.missingGoal, LogWaterIntakeUseCase.Failure.missingDailyGoal),
        (.goalDayMismatch, .goalDayMismatch)
    ])
    func changedGoalDuringSaveUsesIntakeErrors(
        _ repositoryFailure: HydrationRepositoryError,
        expectedFailure: LogWaterIntakeUseCase.Failure
    ) async throws {
        let date = HydrationUseCaseFixtures.now
        let goal = try HydrationGoal(date: date, targetMillilitres: 2_000)
        let repository = MockHydrationRepository(
            goal: goal, failingOperation: .saveIntake, injectedFailure: repositoryFailure
        )
        let useCase = LogWaterIntakeUseCase(
            repository: repository, calendar: HydrationUseCaseFixtures.calendar, now: { date }
        )

        await #expect(throws: expectedFailure) {
            try await useCase.execute(amountMillilitres: 250, recordedAt: date)
        }
        #expect(await repository.savedIntakes.isEmpty)
        #expect(!(try #require(expectedFailure.errorDescription)).isEmpty)
        #expect(!(try #require(expectedFailure.recoverySuggestion)).isEmpty)
    }
}

struct UpdateDailyHydrationGoalUseCaseTests {
    @Test("A new daily goal accepts supported target boundaries", arguments: [500, 5_000])
    func supportedTargetCreatesDailyGoal(_ target: Int) async throws {
        let date = HydrationUseCaseFixtures.now
        let calendar = HydrationUseCaseFixtures.calendar
        let repository = MockHydrationRepository()
        let useCase = UpdateDailyHydrationGoalUseCase(repository: repository, calendar: calendar)

        let goal = try await useCase.execute(targetMillilitres: target, on: date)

        #expect(goal.date == calendar.startOfDay(for: date))
        #expect(goal.targetMillilitres == target)
        #expect(await repository.savedGoals == [goal])
    }

    @Test("Updating a target preserves the daily goal identity used by intake records")
    func updatingTargetPreservesGoalIdentity() async throws {
        let date = HydrationUseCaseFixtures.now
        let goal = try HydrationGoal(date: date, targetMillilitres: 2_000)
        let entry = try WaterIntakeEntry(
            goalID: goal.id, amountMillilitres: 250, recordedAt: date, now: date
        )
        let repository = MockHydrationRepository(goal: goal, entries: [entry])
        let useCase = UpdateDailyHydrationGoalUseCase(
            repository: repository, calendar: HydrationUseCaseFixtures.calendar
        )

        let updated = try await useCase.execute(targetMillilitres: 2_500, on: date)

        #expect(updated.id == goal.id)
        #expect(updated.date == goal.date)
        #expect(updated.targetMillilitres == 2_500)
        #expect(await repository.savedGoals == [updated])
        #expect(try await repository.fetchIntakes(for: updated.id, on: date) == [entry])
    }

    @Test("Unsupported daily targets are rejected before reading or saving a goal", arguments: [499, 5_001])
    func unsupportedTargetDoesNotAccessRepository(_ target: Int) async {
        let date = HydrationUseCaseFixtures.now
        let repository = MockHydrationRepository()
        let useCase = UpdateDailyHydrationGoalUseCase(repository: repository)

        await #expect(throws: UpdateDailyHydrationGoalUseCase.Failure.targetOutsideSupportedRange) {
            try await useCase.execute(targetMillilitres: target, on: date)
        }
        #expect(await repository.requestedGoalDates.isEmpty)
        #expect(await repository.savedGoals.isEmpty)
    }

    @Test("A goal from another day cannot be updated for the selected day")
    func wrongDayGoalPreventsTargetUpdate() async throws {
        let date = HydrationUseCaseFixtures.now
        let calendar = HydrationUseCaseFixtures.calendar
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: date))
        let goal = try HydrationGoal(date: yesterday, targetMillilitres: 2_000)
        let repository = MockHydrationRepository(goal: goal)
        let useCase = UpdateDailyHydrationGoalUseCase(repository: repository, calendar: calendar)

        await #expect(throws: UpdateDailyHydrationGoalUseCase.Failure.goalDayMismatch) {
            try await useCase.execute(targetMillilitres: 2_500, on: date)
        }
        #expect(await repository.savedGoals.isEmpty)
    }

    @Test("Daily goal edits explain goal loading and saving failures", arguments: [
        (MockHydrationRepository.Operation.fetchGoal, UpdateDailyHydrationGoalUseCase.Failure.unableToLoadDailyGoal),
        (.saveGoal, .unableToSaveDailyGoal)
    ])
    func goalEditingFailuresUseDomainErrors(
        _ operation: MockHydrationRepository.Operation,
        expectedFailure: UpdateDailyHydrationGoalUseCase.Failure
    ) async throws {
        let date = HydrationUseCaseFixtures.now
        let goal = try HydrationGoal(date: date, targetMillilitres: 2_000)
        let repository = MockHydrationRepository(goal: goal, failingOperation: operation)
        let useCase = UpdateDailyHydrationGoalUseCase(
            repository: repository, calendar: HydrationUseCaseFixtures.calendar
        )

        await #expect(throws: expectedFailure) {
            try await useCase.execute(targetMillilitres: 2_500, on: date)
        }
        #expect(await repository.savedGoals.isEmpty)
        #expect(!(try #require(expectedFailure.errorDescription)).isEmpty)
        #expect(!(try #require(expectedFailure.recoverySuggestion)).isEmpty)
    }

    @Test("Conflicting goal saves report the correct daily goal error", arguments: [
        (HydrationRepositoryError.duplicateDailyGoal, UpdateDailyHydrationGoalUseCase.Failure.dailyGoalAlreadyExists),
        (.goalDayMismatch, .goalDayMismatch)
    ])
    func conflictingGoalSaveUsesDomainErrors(
        _ repositoryFailure: HydrationRepositoryError,
        expectedFailure: UpdateDailyHydrationGoalUseCase.Failure
    ) async throws {
        let date = HydrationUseCaseFixtures.now
        let goal = try HydrationGoal(date: date, targetMillilitres: 2_000)
        let repository = MockHydrationRepository(
            goal: goal, failingOperation: .saveGoal, injectedFailure: repositoryFailure
        )
        let useCase = UpdateDailyHydrationGoalUseCase(
            repository: repository, calendar: HydrationUseCaseFixtures.calendar
        )

        await #expect(throws: expectedFailure) {
            try await useCase.execute(targetMillilitres: 2_500, on: date)
        }
        #expect(await repository.savedGoals.isEmpty)
        #expect(!(try #require(expectedFailure.errorDescription)).isEmpty)
        #expect(!(try #require(expectedFailure.recoverySuggestion)).isEmpty)
    }
}

struct FetchTodayHydrationProgressUseCaseTests {
    @Test("Today's progress uses today's goal and ignores unrelated intake records")
    func todayProgressUsesDailyGoalAndIntakes() async throws {
        let date = HydrationUseCaseFixtures.now
        let calendar = HydrationUseCaseFixtures.calendar
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: date))
        let goal = try HydrationGoal(date: date, targetMillilitres: 2_000)
        let entries = try [
            WaterIntakeEntry(goalID: goal.id, amountMillilitres: 250, recordedAt: date, now: date),
            WaterIntakeEntry(goalID: goal.id, amountMillilitres: 750, recordedAt: date, now: date),
            WaterIntakeEntry(goalID: goal.id, amountMillilitres: 500, recordedAt: yesterday, now: date),
            WaterIntakeEntry(goalID: UUID(), amountMillilitres: 500, recordedAt: date, now: date)
        ]
        let repository = MockHydrationRepository(goal: goal, entries: entries)
        let useCase = FetchTodayHydrationProgressUseCase(
            repository: repository, calendar: calendar, now: { date }
        )

        let progress = try await useCase.execute()

        #expect(progress.goal == goal)
        #expect(progress.consumedMillilitres == 1_000)
        #expect(progress.remainingMillilitres == 1_000)
        #expect(progress.completionFraction == 0.5)
        #expect(!progress.isGoalReached)
        #expect(await repository.requestedGoalDates == [date])
        #expect(await repository.intakeQueries == [.init(goalID: goal.id, date: date)])
    }

    @Test("Today's progress requires today's daily goal before querying water intake")
    func missingTodayGoalPreventsIntakeQuery() async {
        let date = HydrationUseCaseFixtures.now
        let repository = MockHydrationRepository()
        let useCase = FetchTodayHydrationProgressUseCase(repository: repository, now: { date })

        await #expect(throws: FetchTodayHydrationProgressUseCase.Failure.missingTodayGoal) {
            try await useCase.execute()
        }
        #expect(await repository.intakeQueries.isEmpty)
    }

    @Test("Today's progress reports goal and intake loading failures in domain terms", arguments: [
        (MockHydrationRepository.Operation.fetchGoal, FetchTodayHydrationProgressUseCase.Failure.unableToLoadTodayGoal),
        (.fetchIntakes, .unableToLoadTodayIntakes)
    ])
    func todayLoadingFailuresUseDomainErrors(
        _ operation: MockHydrationRepository.Operation,
        expectedFailure: FetchTodayHydrationProgressUseCase.Failure
    ) async throws {
        let date = HydrationUseCaseFixtures.now
        let goal = try HydrationGoal(date: date, targetMillilitres: 2_000)
        let repository = MockHydrationRepository(goal: goal, failingOperation: operation)
        let useCase = FetchTodayHydrationProgressUseCase(
            repository: repository, calendar: HydrationUseCaseFixtures.calendar, now: { date }
        )

        await #expect(throws: expectedFailure) {
            try await useCase.execute()
        }
        #expect(!(try #require(expectedFailure.recoverySuggestion)).isEmpty)
    }

    @Test("A previous day's goal cannot be used to display today's progress")
    func wrongDayGoalPreventsTodayProgress() async throws {
        let date = HydrationUseCaseFixtures.now
        let calendar = HydrationUseCaseFixtures.calendar
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: date))
        let goal = try HydrationGoal(date: yesterday, targetMillilitres: 2_000)
        let repository = MockHydrationRepository(goal: goal)
        let useCase = FetchTodayHydrationProgressUseCase(repository: repository, calendar: calendar, now: { date })

        await #expect(throws: FetchTodayHydrationProgressUseCase.Failure.goalNotForToday) {
            try await useCase.execute()
        }
        #expect(await repository.intakeQueries.isEmpty)
    }
}
