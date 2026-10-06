import Foundation

// Keep database types out of this contract so use cases can use an in-memory mock.
protocol HydrationRepository: Sendable {
    func fetchGoal(on date: Date) async throws -> HydrationGoal?
    func saveGoal(_ goal: HydrationGoal) async throws
    func fetchIntakes(for goalID: UUID, on date: Date) async throws -> [WaterIntakeEntry]
    func saveIntake(_ entry: WaterIntakeEntry) async throws
}

enum HydrationRepositoryError: LocalizedError, Equatable {
    case storageUnavailable
    case readFailed
    case saveFailed
    case invalidStoredData
    case missingGoal
    case duplicateDailyGoal
    case goalDayMismatch
    case invalidDay

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            "Your saved hydration data could not be opened."
        case .readFailed:
            "Your hydration goal or water intake records could not be loaded."
        case .saveFailed:
            "Your hydration changes could not be saved."
        case .invalidStoredData:
            "A saved hydration goal or water intake record is incomplete or invalid."
        case .missingGoal:
            "This water intake record has no saved daily goal."
        case .duplicateDailyGoal:
            "A hydration goal already exists for this day."
        case .goalDayMismatch:
            "The hydration goal and drinking date do not belong to the same day."
        case .invalidDay:
            "The selected hydration day could not be determined."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .storageUnavailable, .readFailed:
            "Close and reopen the app, then try loading your hydration history again."
        case .saveFailed:
            "Check that your device has free storage, then try saving again."
        case .invalidStoredData:
            "Review your hydration history and correct the affected goal or intake record."
        case .missingGoal:
            "Save a daily goal before recording water for that day."
        case .duplicateDailyGoal:
            "Update the existing daily goal instead of creating another one."
        case .goalDayMismatch:
            "Keep the goal on its original day and record water against the matching day's goal."
        case .invalidDay:
            "Choose another date and check your device's calendar settings."
        }
    }
}
