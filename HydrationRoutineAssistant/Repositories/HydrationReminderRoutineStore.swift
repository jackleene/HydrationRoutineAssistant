import Foundation

@MainActor
protocol HydrationReminderRoutineStore {
    func load() throws -> HydrationReminderRoutine?
    func save(_ routine: HydrationReminderRoutine) throws
}

enum HydrationRoutineStoreError: LocalizedError {
    case unreadablePreferences
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .unreadablePreferences: "Your saved reminder routine could not be read."
        case .saveFailed: "Your reminder routine could not be saved."
        }
    }

    var recoverySuggestion: String? {
        "Review the reminder times and save your routine again."
    }
}
