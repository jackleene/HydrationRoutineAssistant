import Foundation

@MainActor
protocol HydrationReminderRoutineStore {
    func load() throws -> HydrationReminderRoutine?
    func save(_ routine: HydrationReminderRoutine) throws
}

@MainActor
protocol HydrationReminderScheduler {
    func permission() async -> HydrationNotificationPermission
    func requestPermission() async throws -> Bool
    func replaceReminders(with reminders: [HydrationReminder], calendar: Calendar) async throws
    func pendingReminders() async -> [HydrationReminder]
    func sendPreview() async throws
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
