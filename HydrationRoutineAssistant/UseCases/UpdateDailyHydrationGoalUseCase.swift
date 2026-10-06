import Foundation

struct UpdateDailyHydrationGoalUseCase: Sendable {
    private let repository: any HydrationRepository
    private let calendar: Calendar

    init(repository: any HydrationRepository, calendar: Calendar = .current) {
        self.repository = repository
        self.calendar = calendar
    }

    func execute(targetMillilitres: Int, on date: Date) async throws -> HydrationGoal {
        guard HydrationGoal.supportedTargetMillilitres.contains(targetMillilitres) else {
            throw Failure.targetOutsideSupportedRange
        }

        let existingGoal: HydrationGoal?
        do {
            existingGoal = try await repository.fetchGoal(on: date)
        } catch {
            throw Failure.unableToLoadDailyGoal
        }
        if let existingGoal {
            guard calendar.isDate(existingGoal.date, inSameDayAs: date) else {
                throw Failure.goalDayMismatch
            }
        }

        let goal: HydrationGoal
        do {
            // Preserve the ID and date so existing intake records keep their daily goal association.
            goal = try HydrationGoal(
                id: existingGoal?.id ?? UUID(),
                date: existingGoal?.date ?? calendar.startOfDay(for: date),
                targetMillilitres: targetMillilitres
            )
        } catch {
            throw Failure.targetOutsideSupportedRange
        }

        do {
            try await repository.saveGoal(goal)
        } catch HydrationRepositoryError.duplicateDailyGoal {
            throw Failure.dailyGoalAlreadyExists
        } catch HydrationRepositoryError.goalDayMismatch {
            throw Failure.goalDayMismatch
        } catch {
            throw Failure.unableToSaveDailyGoal
        }
        return goal
    }

    enum Failure: LocalizedError, Equatable {
        case targetOutsideSupportedRange
        case goalDayMismatch
        case dailyGoalAlreadyExists
        case unableToLoadDailyGoal
        case unableToSaveDailyGoal

        var errorDescription: String? {
            switch self {
            case .targetOutsideSupportedRange:
                HydrationGoal.ValidationError.targetOutsideSupportedRange.errorDescription
            case .goalDayMismatch:
                "The saved hydration goal belongs to a different day."
            case .dailyGoalAlreadyExists:
                "A hydration goal was already saved for this day."
            case .unableToLoadDailyGoal:
                "Your daily hydration goal could not be loaded for editing."
            case .unableToSaveDailyGoal:
                "Your daily hydration goal could not be saved."
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .targetOutsideSupportedRange:
                HydrationGoal.ValidationError.targetOutsideSupportedRange.recoverySuggestion
            case .goalDayMismatch:
                "Check the selected day and reload its hydration goal before editing."
            case .dailyGoalAlreadyExists:
                "Reload the existing goal, then update its target."
            case .unableToLoadDailyGoal:
                "Reload the goal for the selected day, then try editing it again."
            case .unableToSaveDailyGoal:
                "Keep your chosen target and try saving the daily goal again."
            }
        }
    }
}
