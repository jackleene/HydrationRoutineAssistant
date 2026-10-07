import Foundation

struct FetchHydrationHistoryUseCase: Sendable {
    let repository: any HydrationRepository
    let calendar: Calendar

    func execute(on date: Date) async throws -> HydrationDayHistory {
        do {
            guard let goal = try await repository.fetchGoal(on: date) else {
                return HydrationDayHistory(date: date, progress: nil, entries: [])
            }
            guard calendar.isDate(goal.date, inSameDayAs: date) else {
                throw Failure.goalDayMismatch
            }
            let entries = try await repository.fetchIntakes(for: goal.id, on: date)
                .filter { $0.goalID == goal.id && calendar.isDate($0.recordedAt, inSameDayAs: date) }
                .sorted { $0.recordedAt > $1.recordedAt }
            return HydrationDayHistory(
                date: date, progress: HydrationProgress(goal: goal, entries: entries, calendar: calendar),
                entries: entries
            )
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.unableToLoadHistory
        }
    }

    enum Failure: LocalizedError, Equatable {
        case goalDayMismatch
        case unableToLoadHistory

        var errorDescription: String? {
            switch self {
            case .goalDayMismatch: "The saved hydration goal does not match the selected history day."
            case .unableToLoadHistory: "Water intake history for this day could not be loaded."
            }
        }

        var recoverySuggestion: String? { "Check the selected date, then reload your hydration history." }
    }
}

@MainActor
struct SaveHydrationReminderRoutineUseCase {
    let store: any HydrationReminderRoutineStore

    func execute(_ routine: HydrationReminderRoutine) throws {
        do {
            try routine.validate()
        } catch HydrationReminderRoutine.ValidationError.invalidTimeWindow {
            throw Failure.invalidTimeWindow
        } catch HydrationReminderRoutine.ValidationError.unsupportedInterval {
            throw Failure.unsupportedInterval
        } catch {
            throw Failure.missingWeekdays
        }
        do {
            try store.save(routine)
        } catch {
            throw Failure.unableToSaveRoutine
        }
    }

    enum Failure: LocalizedError, Equatable {
        case invalidTimeWindow, unsupportedInterval, missingWeekdays, unableToSaveRoutine

        var errorDescription: String? {
            switch self {
            case .invalidTimeWindow: "The reminder end time must be later than the start time on the same day."
            case .unsupportedInterval: "Choose a reminder interval from 15 to 180 minutes in 15-minute steps."
            case .missingWeekdays: "Choose at least one day for your reminder routine."
            case .unableToSaveRoutine: "Your reminder routine could not be saved."
            }
        }

        var recoverySuggestion: String? { "Adjust your reminder preferences, then save the routine again." }
    }
}
