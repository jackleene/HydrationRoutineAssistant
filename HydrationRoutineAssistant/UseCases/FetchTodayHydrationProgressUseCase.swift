import Foundation

struct FetchTodayHydrationProgressUseCase: Sendable {
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

    func execute() async throws -> HydrationProgress {
        // One clock reading keeps both queries on the same day if execution crosses midnight.
        let today = now()
        let savedGoal: HydrationGoal?
        do {
            savedGoal = try await repository.fetchGoal(on: today)
        } catch {
            throw Failure.unableToLoadTodayGoal
        }
        guard let goal = savedGoal else { throw Failure.missingTodayGoal }
        guard calendar.isDate(goal.date, inSameDayAs: today) else {
            throw Failure.goalNotForToday
        }

        let entries: [WaterIntakeEntry]
        do {
            entries = try await repository.fetchIntakes(for: goal.id, on: today)
        } catch {
            throw Failure.unableToLoadTodayIntakes
        }
        return HydrationProgress(goal: goal, entries: entries, calendar: calendar)
    }

    enum Failure: LocalizedError, Equatable {
        case missingTodayGoal
        case goalNotForToday
        case unableToLoadTodayGoal
        case unableToLoadTodayIntakes

        var errorDescription: String? {
            switch self {
            case .missingTodayGoal:
                "Today's hydration progress needs a daily goal."
            case .goalNotForToday:
                "The saved hydration goal does not belong to today."
            case .unableToLoadTodayGoal:
                "Today's hydration goal could not be loaded."
            case .unableToLoadTodayIntakes:
                "Today's water intake records could not be loaded."
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .missingTodayGoal:
                "Set today's hydration goal, then return to your progress."
            case .goalNotForToday:
                "Check your device's date and reload today's hydration goal."
            case .unableToLoadTodayGoal:
                "Try loading today's goal again before checking your progress."
            case .unableToLoadTodayIntakes:
                "Reload today's intake records to refresh your hydration progress."
            }
        }
    }
}
