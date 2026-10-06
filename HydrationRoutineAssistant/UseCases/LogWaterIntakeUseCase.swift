import Foundation

struct LogWaterIntakeUseCase: Sendable {
    private let repository: any HydrationRepository
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(
        repository: any HydrationRepository,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.calendar = calendar
        self.now = now
    }

    func execute(amountMillilitres: Int, recordedAt: Date) async throws -> WaterIntakeEntry {
        let referenceTime = now()
        guard WaterIntakeEntry.supportedAmountMillilitres.contains(amountMillilitres) else {
            throw Failure.amountOutsideSupportedRange
        }
        guard recordedAt <= referenceTime else {
            throw Failure.recordedInFuture
        }

        let savedGoal: HydrationGoal?
        do {
            savedGoal = try await repository.fetchGoal(on: recordedAt)
        } catch {
            throw Failure.unableToLoadDailyGoal
        }
        guard let goal = savedGoal else { throw Failure.missingDailyGoal }
        guard calendar.isDate(goal.date, inSameDayAs: recordedAt) else {
            throw Failure.goalDayMismatch
        }

        let entry: WaterIntakeEntry
        do {
            entry = try WaterIntakeEntry(
                goalID: goal.id, amountMillilitres: amountMillilitres,
                recordedAt: recordedAt, now: referenceTime
            )
        } catch WaterIntakeEntry.ValidationError.recordedInFuture {
            throw Failure.recordedInFuture
        } catch {
            throw Failure.amountOutsideSupportedRange
        }

        do {
            try await repository.saveIntake(entry)
        } catch HydrationRepositoryError.missingGoal {
            throw Failure.missingDailyGoal
        } catch HydrationRepositoryError.goalDayMismatch {
            throw Failure.goalDayMismatch
        } catch {
            throw Failure.unableToSaveIntake
        }
        return entry
    }

    enum Failure: LocalizedError, Equatable {
        case amountOutsideSupportedRange
        case recordedInFuture
        case missingDailyGoal
        case goalDayMismatch
        case unableToLoadDailyGoal
        case unableToSaveIntake

        var errorDescription: String? {
            switch self {
            case .amountOutsideSupportedRange:
                WaterIntakeEntry.ValidationError.amountOutsideSupportedRange.errorDescription
            case .recordedInFuture:
                WaterIntakeEntry.ValidationError.recordedInFuture.errorDescription
            case .missingDailyGoal:
                "Set a daily hydration goal before recording water for this day."
            case .goalDayMismatch:
                "The saved goal does not match the day you drank the water."
            case .unableToLoadDailyGoal:
                "Your daily hydration goal could not be loaded."
            case .unableToSaveIntake:
                "Your water intake record could not be saved."
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .amountOutsideSupportedRange:
                WaterIntakeEntry.ValidationError.amountOutsideSupportedRange.recoverySuggestion
            case .recordedInFuture:
                WaterIntakeEntry.ValidationError.recordedInFuture.recoverySuggestion
            case .missingDailyGoal:
                "Create a goal for the drinking day, then record your water intake again."
            case .goalDayMismatch:
                "Check the drinking date and reload the goal for that day."
            case .unableToLoadDailyGoal:
                "Reload the daily goal, then try recording your water intake again."
            case .unableToSaveIntake:
                "Keep the amount and drinking time, then try saving the record again."
            }
        }
    }
}
