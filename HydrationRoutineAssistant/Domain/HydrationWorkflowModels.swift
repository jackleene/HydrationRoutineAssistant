import Foundation

struct HydrationDayHistory: Equatable, Sendable {
    let date: Date
    let progress: HydrationProgress?
    let entries: [WaterIntakeEntry]
}

struct HydrationReminderRoutine: Codable, Equatable, Sendable {
    let isEnabled: Bool
    let startMinute: Int
    let endMinute: Int
    let intervalMinutes: Int
    let weekdays: Set<Int>

    static let initial = HydrationReminderRoutine(
        isEnabled: false, startMinute: 9 * 60, endMinute: 17 * 60,
        intervalMinutes: 60, weekdays: [2, 3, 4, 5, 6]
    )

    func validate() throws {
        guard (0..<1_440).contains(startMinute), (0..<1_440).contains(endMinute),
              startMinute < endMinute else { throw ValidationError.invalidTimeWindow }
        guard (15...180).contains(intervalMinutes), intervalMinutes.isMultiple(of: 15) else {
            throw ValidationError.unsupportedInterval
        }
        guard !weekdays.isEmpty, weekdays.isSubset(of: Set(1...7)) else {
            throw ValidationError.missingWeekdays
        }
    }

    enum ValidationError: Error {
        case invalidTimeWindow
        case unsupportedInterval
        case missingWeekdays
    }
}

enum HydrationWeekday: Int, CaseIterable, Identifiable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    static let displayOrder: [Self] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var title: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }

    var shortTitle: String { String(title.prefix(3)) }
}
