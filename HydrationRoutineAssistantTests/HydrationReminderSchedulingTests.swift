import Foundation
import Testing
@testable import HydrationRoutineAssistant

private enum ReminderFixtures {
    static let now = Date(timeIntervalSince1970: 1_791_374_400)
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    static let enabled = HydrationReminderRoutine(
        isEnabled: true, startMinute: 540, endMinute: 1_020, intervalMinutes: 60, weekdays: [2, 3, 4, 5, 6]
    )
}

struct PlanHydrationRemindersTests {
    @Test("Water breaks use selected weekdays, skip passed times and exclude the end of the window")
    func routineProducesFutureWaterBreaks() throws {
        let calendar = ReminderFixtures.calendar
        let reminders = try PlanHydrationRemindersUseCase(calendar: calendar)
            .execute(ReminderFixtures.enabled, from: ReminderFixtures.now)

        #expect(reminders.count == 36)
        #expect(reminders.first?.scheduledAt == ReminderFixtures.now.addingTimeInterval(3_600))
        #expect(reminders.allSatisfy { $0.scheduledAt > ReminderFixtures.now })
        #expect(reminders.allSatisfy { [2, 3, 4, 5, 6].contains(calendar.component(.weekday, from: $0.scheduledAt)) })
        #expect(reminders.allSatisfy { (9..<17).contains(calendar.component(.hour, from: $0.scheduledAt)) })
        #expect(reminders.allSatisfy { calendar.component(.minute, from: $0.scheduledAt) == 0 })
        #expect(Set(reminders.map(\.id)).count == 36)
    }

    @Test("Dense routines keep only the earliest 60 future reminders")
    func denseRoutineHasBoundedQueue() throws {
        let routine = HydrationReminderRoutine(
            isEnabled: true, startMinute: 0, endMinute: 1_439, intervalMinutes: 15, weekdays: Set(1...7)
        )
        let reminders = try PlanHydrationRemindersUseCase(calendar: ReminderFixtures.calendar)
            .execute(routine, from: ReminderFixtures.now)

        #expect(reminders.count == 60)
        #expect(reminders.first?.scheduledAt == ReminderFixtures.now.addingTimeInterval(900))
        #expect(reminders.map(\.scheduledAt) == reminders.map(\.scheduledAt).sorted())
        #expect(Set(reminders.map(\.id)).count == 60)
    }

    @Test("Reaching today's goal pauses today's reminders without dropping future routine days")
    func completedDayDoesNotScheduleMoreWaterBreaks() throws {
        let calendar = ReminderFixtures.calendar
        let reminders = try PlanHydrationRemindersUseCase(calendar: calendar).execute(
            ReminderFixtures.enabled, from: ReminderFixtures.now, completedDay: ReminderFixtures.now
        )
        #expect(reminders.count == 32)
        #expect(reminders.allSatisfy { !calendar.isDate($0.scheduledAt, inSameDayAs: ReminderFixtures.now) })
    }

    @Test("A disabled routine produces no water-break reminders")
    func disabledRoutineHasEmptyPlan() throws {
        #expect(try PlanHydrationRemindersUseCase(calendar: ReminderFixtures.calendar)
            .execute(ReminderFixtures.enabled.disablingReminders(), from: ReminderFixtures.now).isEmpty)
    }

    @Test("The shortest and longest supported intervals produce valid water breaks", arguments: [
        (interval: 15, count: 14), (interval: 180, count: 7)
    ])
    func supportedIntervalBoundaries(_ input: (interval: Int, count: Int)) throws {
        let routine = HydrationReminderRoutine(
            isEnabled: true, startMinute: 780, endMinute: 810,
            intervalMinutes: input.interval, weekdays: Set(1...7)
        )
        let reminders = try PlanHydrationRemindersUseCase(calendar: ReminderFixtures.calendar)
            .execute(routine, from: ReminderFixtures.now)

        #expect(reminders.count == input.count)
        #expect(reminders.first?.scheduledAt == ReminderFixtures.now.addingTimeInterval(3_600))
    }

    @Test("The seven-day plan excludes passed times and the eighth calendar day")
    func planningWindowEndsAfterSixFutureDays() throws {
        let calendar = ReminderFixtures.calendar
        let routine = HydrationReminderRoutine(
            isEnabled: true, startMinute: 0, endMinute: 1,
            intervalMinutes: 180, weekdays: Set(1...7)
        )
        let reminders = try PlanHydrationRemindersUseCase(calendar: calendar)
            .execute(routine, from: ReminderFixtures.now)
        let midnight = calendar.startOfDay(for: ReminderFixtures.now)

        #expect(reminders.count == 6)
        #expect(reminders.first?.scheduledAt == midnight.addingTimeInterval(86_400))
        #expect(reminders.last?.scheduledAt == midnight.addingTimeInterval(6 * 86_400))
    }

    @Test("Invalid routine rules use domain errors before building a queue", arguments: [
        (start: 540, end: 540, interval: 60, days: Set([2]), failure: PlanHydrationRemindersUseCase.Failure.invalidTimeWindow),
        (start: -1, end: 1_020, interval: 60, days: Set([2]), failure: .invalidTimeWindow),
        (start: 540, end: 1_440, interval: 60, days: Set([2]), failure: .invalidTimeWindow),
        (start: 540, end: 1_020, interval: 14, days: Set([2]), failure: .unsupportedInterval),
        (start: 540, end: 1_020, interval: 16, days: Set([2]), failure: .unsupportedInterval),
        (start: 540, end: 1_020, interval: 181, days: Set([2]), failure: .unsupportedInterval),
        (start: 540, end: 1_020, interval: 60, days: Set<Int>(), failure: .missingWeekdays),
        (start: 540, end: 1_020, interval: 60, days: Set([0]), failure: .missingWeekdays),
        (start: 540, end: 1_020, interval: 60, days: Set([8]), failure: .missingWeekdays)
    ])
    func invalidRoutineHasNoPlan(
        _ input: (start: Int, end: Int, interval: Int, days: Set<Int>, failure: PlanHydrationRemindersUseCase.Failure)
    ) {
        let routine = HydrationReminderRoutine(isEnabled: true, startMinute: input.start, endMinute: input.end,
                                               intervalMinutes: input.interval, weekdays: input.days)
        #expect(throws: input.failure) {
            try PlanHydrationRemindersUseCase(calendar: ReminderFixtures.calendar).execute(routine, from: ReminderFixtures.now)
        }
    }

    @Test("Sydney clock changes skip nonexistent times and do not duplicate a repeated hour", arguments: [
        (month: 4, day: 5, expectedHours: [1, 1, 2, 2, 3, 3]),
        (month: 10, day: 4, expectedHours: [1, 1, 3, 3])
    ])
    func daylightSavingUsesValidLocalTimes(_ input: (month: Int, day: Int, expectedHours: [Int])) throws {
        var calendar = ReminderFixtures.calendar
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: input.month, day: input.day)))
        let routine = HydrationReminderRoutine(isEnabled: true, startMinute: 60, endMinute: 240,
                                               intervalMinutes: 30, weekdays: [1])
        let reminders = try PlanHydrationRemindersUseCase(calendar: calendar).execute(routine, from: date)
        #expect(reminders.map { calendar.component(.hour, from: $0.scheduledAt) } == input.expectedHours)
        #expect(Set(reminders.map(\.scheduledAt)).count == reminders.count)
    }
}

@MainActor
struct ScheduleHydrationRemindersTests {
    @Test("Invalid edits leave the saved routine and pending reminders unchanged")
    func invalidEditDoesNotAffectExistingRoutine() async {
        let store = ReminderPreferenceMock()
        store.saved = ReminderFixtures.enabled
        let scheduler = ReminderSchedulerMock(permission: .notDetermined)
        let previous = [HydrationReminder(scheduledAt: ReminderFixtures.now.addingTimeInterval(60))]
        scheduler.pending = previous
        let invalid = HydrationReminderRoutine(
            isEnabled: true, startMinute: 540, endMinute: 1_020, intervalMinutes: 60, weekdays: []
        )

        await #expect(throws: PlanHydrationRemindersUseCase.Failure.missingWeekdays) {
            try await ScheduleHydrationRemindersUseCase(
                store: store, scheduler: scheduler, calendar: ReminderFixtures.calendar
            ).execute(invalid, at: ReminderFixtures.now)
        }

        #expect(store.saved == ReminderFixtures.enabled)
        #expect(scheduler.pending == previous)
        #expect(scheduler.permissionChecks == 0)
        #expect(scheduler.permissionRequests == 0)
        #expect(scheduler.replacements == 0)
    }

    @Test("A failed preference save preserves the previous queue without requesting permission")
    func failedSavePreservesExistingRoutine() async {
        let store = ReminderPreferenceMock(failsSave: true)
        let previousRoutine = ReminderFixtures.enabled.disablingReminders()
        store.saved = previousRoutine
        let scheduler = ReminderSchedulerMock(permission: .notDetermined)
        let previous = [HydrationReminder(scheduledAt: ReminderFixtures.now.addingTimeInterval(60))]
        scheduler.pending = previous

        await #expect(throws: ScheduleHydrationRemindersUseCase.Failure.unableToSaveRoutine) {
            try await ScheduleHydrationRemindersUseCase(
                store: store, scheduler: scheduler, calendar: ReminderFixtures.calendar
            ).execute(ReminderFixtures.enabled, at: ReminderFixtures.now)
        }

        #expect(store.saved == previousRoutine)
        #expect(scheduler.pending == previous)
        #expect(scheduler.permissionChecks == 0)
        #expect(scheduler.permissionRequests == 0)
        #expect(scheduler.replacements == 0)
    }

    @Test("Saving an enabled routine requests permission once and replaces the reminder queue")
    func permissionGrantedSchedulesRoutine() async throws {
        let store = ReminderPreferenceMock()
        let scheduler = ReminderSchedulerMock(permission: .notDetermined)
        let reminders = try await ScheduleHydrationRemindersUseCase(
            store: store, scheduler: scheduler, calendar: ReminderFixtures.calendar
        ).execute(ReminderFixtures.enabled, at: ReminderFixtures.now)

        #expect(store.saved == ReminderFixtures.enabled)
        #expect(scheduler.permissionRequests == 1)
        #expect(scheduler.pending == reminders)
        #expect(scheduler.replacements == 1)
        #expect(reminders.count == 36)
    }

    @Test("Denied notification permission preserves preferences but clears pending water breaks")
    func deniedPermissionDoesNotSchedule() async {
        let store = ReminderPreferenceMock()
        let scheduler = ReminderSchedulerMock(permission: .denied)
        scheduler.pending = [HydrationReminder(scheduledAt: ReminderFixtures.now.addingTimeInterval(60))]
        await #expect(throws: ScheduleHydrationRemindersUseCase.Failure.notificationsNotAllowed) {
            try await ScheduleHydrationRemindersUseCase(store: store, scheduler: scheduler, calendar: ReminderFixtures.calendar)
                .execute(ReminderFixtures.enabled, at: ReminderFixtures.now)
        }
        #expect(store.saved == ReminderFixtures.enabled)
        #expect(scheduler.pending.isEmpty)
        #expect(scheduler.permissionRequests == 0)
    }

    @Test("Declining the first permission request saves preferences but clears water breaks")
    func firstPermissionRequestIsDeclined() async {
        let store = ReminderPreferenceMock()
        let scheduler = ReminderSchedulerMock(permission: .notDetermined)
        scheduler.grantsPermission = false
        scheduler.pending = [HydrationReminder(scheduledAt: ReminderFixtures.now.addingTimeInterval(60))]

        await #expect(throws: ScheduleHydrationRemindersUseCase.Failure.notificationsNotAllowed) {
            try await ScheduleHydrationRemindersUseCase(
                store: store, scheduler: scheduler, calendar: ReminderFixtures.calendar
            ).execute(ReminderFixtures.enabled, at: ReminderFixtures.now)
        }

        #expect(store.saved == ReminderFixtures.enabled)
        #expect(scheduler.permissionRequests == 1)
        #expect(scheduler.currentPermission == .denied)
        #expect(scheduler.pending.isEmpty)
        #expect(scheduler.replacements == 1)
    }

    @Test("Refreshing a saved routine never opens the notification permission prompt")
    func automaticRefreshDoesNotAskPermission() async {
        let scheduler = ReminderSchedulerMock(permission: .notDetermined)
        await #expect(throws: ScheduleHydrationRemindersUseCase.Failure.notificationsNotAllowed) {
            try await ScheduleHydrationRemindersUseCase(
                store: ReminderPreferenceMock(), scheduler: scheduler, calendar: ReminderFixtures.calendar
            ).execute(ReminderFixtures.enabled, at: ReminderFixtures.now, requestPermission: false)
        }
        #expect(scheduler.permissionRequests == 0)
        #expect(scheduler.pending.isEmpty)
    }

    @Test("Turning off a routine cancels reminders even when permission was denied")
    func disablingRoutineCancelsWithoutPermission() async throws {
        let store = ReminderPreferenceMock()
        let scheduler = ReminderSchedulerMock(permission: .denied)
        scheduler.pending = [HydrationReminder(scheduledAt: ReminderFixtures.now.addingTimeInterval(60))]
        let disabled = ReminderFixtures.enabled.disablingReminders()
        let reminders = try await ScheduleHydrationRemindersUseCase(
            store: store, scheduler: scheduler, calendar: ReminderFixtures.calendar
        ).execute(disabled, at: ReminderFixtures.now)

        #expect(reminders.isEmpty)
        #expect(scheduler.pending.isEmpty)
        #expect(store.saved == disabled)
        #expect(scheduler.permissionRequests == 0)
    }

    @Test("Preference, permission and scheduling failures report the failed step", arguments: [
        (save: true, permission: false, schedule: false, saved: false, failure: ScheduleHydrationRemindersUseCase.Failure.unableToSaveRoutine),
        (save: false, permission: true, schedule: false, saved: true, failure: .unableToRequestPermission),
        (save: false, permission: false, schedule: true, saved: true, failure: .unableToScheduleReminders)
    ])
    func failuresUseDomainFeedback(
        _ input: (save: Bool, permission: Bool, schedule: Bool, saved: Bool, failure: ScheduleHydrationRemindersUseCase.Failure)
    ) async {
        let store = ReminderPreferenceMock(failsSave: input.save)
        let scheduler = ReminderSchedulerMock(permission: .notDetermined)
        scheduler.failsPermission = input.permission
        scheduler.failsReplacement = input.schedule
        await #expect(throws: input.failure) {
            try await ScheduleHydrationRemindersUseCase(store: store, scheduler: scheduler, calendar: ReminderFixtures.calendar)
                .execute(ReminderFixtures.enabled, at: ReminderFixtures.now)
        }
        #expect((store.saved != nil) == input.saved)
        #expect(scheduler.pending.isEmpty)
    }

    @Test("Authorized stakeholders can send one test water-break reminder")
    func previewSchedulesOneReminder() async throws {
        let scheduler = ReminderSchedulerMock(permission: .authorized)
        try await SendHydrationReminderPreviewUseCase(scheduler: scheduler).execute()
        #expect(scheduler.previews == 1)
        #expect(scheduler.permissionRequests == 0)
    }

    @Test("A test reminder cannot bypass missing notification permission", arguments: [
        HydrationNotificationPermission.denied, .notDetermined
    ])
    func previewRespectsDeniedPermission(permission: HydrationNotificationPermission) async {
        let scheduler = ReminderSchedulerMock(permission: permission)
        await #expect(throws: SendHydrationReminderPreviewUseCase.Failure.notificationsNotAllowed) {
            try await SendHydrationReminderPreviewUseCase(scheduler: scheduler).execute()
        }
        #expect(scheduler.previews == 0)
        #expect(scheduler.permissionRequests == 0)
    }

    @Test("A preview scheduling failure does not change the saved reminder queue")
    func failedPreviewPreservesRoutineQueue() async {
        let scheduler = ReminderSchedulerMock(permission: .authorized)
        scheduler.failsPreview = true
        let previous = [HydrationReminder(scheduledAt: ReminderFixtures.now.addingTimeInterval(60))]
        scheduler.pending = previous

        await #expect(throws: SendHydrationReminderPreviewUseCase.Failure.unableToSendPreview) {
            try await SendHydrationReminderPreviewUseCase(scheduler: scheduler).execute()
        }

        #expect(scheduler.pending == previous)
        #expect(scheduler.previews == 0)
        #expect(scheduler.permissionRequests == 0)
        #expect(scheduler.replacements == 0)
    }

    @Test("Turn off uses saved preferences even when the edited form has no selected days")
    func stopIgnoresUnsavedInvalidForm() async {
        let store = ReminderPreferenceMock()
        store.saved = ReminderFixtures.enabled
        let scheduler = ReminderSchedulerMock(permission: .authorized)
        scheduler.pending = [HydrationReminder(scheduledAt: Date().addingTimeInterval(60))]
        let model = HydrationWorkspaceViewModel(
            repository: MockHydrationRepository(), routineStore: store, reminderScheduler: scheduler
        )
        model.routineWeekdays = []

        await model.stopReminders()

        #expect(store.saved?.isEnabled == false)
        #expect(scheduler.pending.isEmpty)
        #expect(!model.routineEnabled)
        #expect(model.scheduledReminderCount == 0)
        #expect(model.routineConfirmation == "Water-break reminders turned off.")
        #expect(!model.isSavingRoutine)
    }

    @Test("The completed daily goal prevents the workspace from scheduling more reminders today")
    func completedGoalPausesTodayQueue() async throws {
        let date = Date()
        let calendar = ReminderFixtures.calendar
        let goal = try HydrationGoal(date: date, targetMillilitres: 500)
        let intake = try WaterIntakeEntry(goalID: goal.id, amountMillilitres: 500, recordedAt: date, now: date)
        let store = ReminderPreferenceMock()
        store.saved = HydrationReminderRoutine(isEnabled: true, startMinute: 540, endMinute: 600,
                                               intervalMinutes: 60, weekdays: Set(1...7))
        let scheduler = ReminderSchedulerMock(permission: .authorized)
        let model = HydrationWorkspaceViewModel(
            repository: MockHydrationRepository(goal: goal, entries: [intake]), routineStore: store,
            calendar: calendar, reminderScheduler: scheduler
        )
        await model.refreshToday()
        await model.refreshReminderSchedule()

        #expect(!scheduler.pending.isEmpty)
        #expect(scheduler.pending.allSatisfy { !calendar.isDate($0.scheduledAt, inSameDayAs: date) })
        #expect(model.scheduledReminderCount == 6)
        #expect(!model.isRefreshingReminders)
    }

    @Test("A goal completed while reminders are being installed reconciles the final queue")
    func goalCompletedDuringSchedulingReconcilesQueue() async throws {
        let date = Date()
        let calendar = ReminderFixtures.calendar
        let goal = try HydrationGoal(date: date, targetMillilitres: 500)
        let intake = try WaterIntakeEntry(goalID: goal.id, amountMillilitres: 500, recordedAt: date, now: date)
        let store = ReminderPreferenceMock()
        store.saved = HydrationReminderRoutine(isEnabled: true, startMinute: 0, endMinute: 1_439,
                                               intervalMinutes: 180, weekdays: Set(1...7))
        let scheduler = ReminderSchedulerMock(permission: .authorized)
        scheduler.pauseFirstReplacement = true
        let model = HydrationWorkspaceViewModel(
            repository: MockHydrationRepository(goal: goal, entries: [intake]), routineStore: store,
            calendar: calendar, reminderScheduler: scheduler
        )
        let saving = Task { await model.saveRoutine() }
        await scheduler.waitUntilPaused()

        await model.refreshToday()
        #expect(model.todayProgress?.isGoalReached == true)
        scheduler.resumeReplacement()
        await saving.value

        #expect(scheduler.pending.allSatisfy { !calendar.isDate($0.scheduledAt, inSameDayAs: date) })
        #expect(scheduler.replacements == 2)
        #expect(!model.isSavingRoutine)
    }
}

@MainActor
private final class ReminderPreferenceMock: HydrationReminderRoutineStore {
    var saved: HydrationReminderRoutine?
    let failsSave: Bool
    init(failsSave: Bool = false) { self.failsSave = failsSave }
    func load() throws -> HydrationReminderRoutine? { saved }
    func save(_ routine: HydrationReminderRoutine) throws {
        if failsSave { throw HydrationRoutineStoreError.saveFailed }
        saved = routine
    }
}

@MainActor
private final class ReminderSchedulerMock: HydrationReminderScheduler {
    var currentPermission: HydrationNotificationPermission
    var pending: [HydrationReminder] = []
    var failsPermission = false
    var failsReplacement = false
    var failsPreview = false
    var grantsPermission = true
    var pauseFirstReplacement = false
    private var pausedReplacement: CheckedContinuation<Void, Never>?
    private var pauseObserver: CheckedContinuation<Void, Never>?
    private(set) var permissionRequests = 0
    private(set) var permissionChecks = 0
    private(set) var replacements = 0
    private(set) var previews = 0

    init(permission: HydrationNotificationPermission) { currentPermission = permission }
    func permission() async -> HydrationNotificationPermission {
        permissionChecks += 1
        return currentPermission
    }
    func requestPermission() async throws -> Bool {
        permissionRequests += 1
        if failsPermission { throw HydrationRoutineStoreError.saveFailed }
        currentPermission = grantsPermission ? .authorized : .denied
        return grantsPermission
    }
    func replaceReminders(with reminders: [HydrationReminder], calendar: Calendar) async throws {
        if pauseFirstReplacement, replacements == 0 {
            await withCheckedContinuation { continuation in
                pausedReplacement = continuation
                pauseObserver?.resume()
                pauseObserver = nil
            }
        }
        if failsReplacement { throw HydrationRoutineStoreError.saveFailed }
        pending = reminders
        replacements += 1
    }
    func pendingReminders() async -> [HydrationReminder] { pending }
    func sendPreview() async throws {
        if failsPreview { throw HydrationRoutineStoreError.saveFailed }
        previews += 1
    }
    func waitUntilPaused() async {
        if pausedReplacement != nil { return }
        await withCheckedContinuation { pauseObserver = $0 }
    }
    func resumeReplacement() {
        pausedReplacement?.resume()
        pausedReplacement = nil
    }
}
