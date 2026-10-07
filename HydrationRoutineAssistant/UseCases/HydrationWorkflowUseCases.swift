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

struct PlanHydrationRemindersUseCase: Sendable {
    static let maximumPendingReminders = 60
    let calendar: Calendar

    func execute(_ routine: HydrationReminderRoutine, from date: Date, completedDay: Date? = nil) throws -> [HydrationReminder] {
        guard routine.isEnabled else { return [] }
        do { try routine.validate() }
        catch HydrationReminderRoutine.ValidationError.invalidTimeWindow { throw Failure.invalidTimeWindow }
        catch HydrationReminderRoutine.ValidationError.unsupportedInterval { throw Failure.unsupportedInterval }
        catch { throw Failure.missingWeekdays }
        var reminders: [HydrationReminder] = []
        let today = calendar.startOfDay(for: date)
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { throw Failure.invalidHydrationDay }
            if let completedDay, calendar.isDate(day, inSameDayAs: completedDay) { continue }
            guard routine.weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
            for minute in stride(from: routine.startMinute, to: routine.endMinute, by: routine.intervalMinutes) {
                // Strict matching skips nonexistent local times during a daylight-saving change.
                guard let time = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day,
                                               matchingPolicy: .strict, repeatedTimePolicy: .first, direction: .forward),
                      calendar.isDate(time, inSameDayAs: day), time > date else { continue }
                reminders.append(HydrationReminder(scheduledAt: time))
                if reminders.count == Self.maximumPendingReminders { return reminders }
            }
        }
        return reminders
    }

    enum Failure: LocalizedError, Equatable {
        case invalidTimeWindow, unsupportedInterval, missingWeekdays, invalidHydrationDay

        var errorDescription: String? {
            switch self {
            case .invalidTimeWindow: "Choose a reminder end time later than the start time on the same day."
            case .unsupportedInterval: "Choose an interval from 15 to 180 minutes in 15-minute steps."
            case .missingWeekdays: "Choose at least one day for your water breaks."
            case .invalidHydrationDay: "The next reminder days could not be determined."
            }
        }
        var recoverySuggestion: String? { "Review your routine times and days, then save again." }
    }
}

@MainActor
struct ScheduleHydrationRemindersUseCase {
    let store: any HydrationReminderRoutineStore
    let scheduler: any HydrationReminderScheduler
    let calendar: Calendar

    func execute(
        _ routine: HydrationReminderRoutine, at date: Date, completedDay: Date? = nil,
        requestPermission: Bool = true
    ) async throws -> [HydrationReminder] {
        let reminders = try PlanHydrationRemindersUseCase(calendar: calendar)
            .execute(routine, from: date, completedDay: completedDay)
        do { try SaveHydrationReminderRoutineUseCase(store: store).execute(routine) }
        catch { throw Failure.unableToSaveRoutine }
        if routine.isEnabled {
            var permission = await scheduler.permission()
            if permission == .notDetermined, requestPermission {
                do { permission = try await scheduler.requestPermission() ? .authorized : .denied }
                catch { throw Failure.unableToRequestPermission }
            }
            guard permission == .authorized else {
                try? await scheduler.replaceReminders(with: [], calendar: calendar)
                throw Failure.notificationsNotAllowed
            }
        }
        do { try await scheduler.replaceReminders(with: reminders, calendar: calendar) }
        catch { throw Failure.unableToScheduleReminders }
        return reminders
    }

    enum Failure: LocalizedError, Equatable {
        case unableToSaveRoutine, unableToRequestPermission, notificationsNotAllowed, unableToScheduleReminders

        var errorDescription: String? {
            switch self {
            case .unableToSaveRoutine: "Your reminder preferences could not be saved."
            case .unableToRequestPermission: "Your routine is saved, but notification permission could not be requested."
            case .notificationsNotAllowed: "Your routine is saved, but notifications are not allowed."
            case .unableToScheduleReminders: "Your routine is saved, but its water-break reminders could not be scheduled."
            }
        }
        var recoverySuggestion: String? {
            switch self {
            case .notificationsNotAllowed: "Allow notifications in Settings, then return to the app to apply your routine."
            default: "Try saving your routine again. You can turn off reminders if you no longer want them."
            }
        }
    }
}

@MainActor
struct SendHydrationReminderPreviewUseCase {
    let scheduler: any HydrationReminderScheduler

    func execute() async throws {
        guard await scheduler.permission() == .authorized else { throw Failure.notificationsNotAllowed }
        do { try await scheduler.sendPreview() }
        catch { throw Failure.unableToSendPreview }
    }

    enum Failure: LocalizedError, Equatable {
        case notificationsNotAllowed, unableToSendPreview
        var errorDescription: String? {
            switch self {
            case .notificationsNotAllowed: "Allow notifications before sending a test water-break reminder."
            case .unableToSendPreview: "The test water-break reminder could not be scheduled."
            }
        }
        var recoverySuggestion: String? { "Save an enabled routine and check notification permission, then try again." }
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
