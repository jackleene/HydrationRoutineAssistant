import Foundation
import Observation

struct HydrationIssue: Equatable {
    let message: String
    let recovery: String?

    init(_ error: any Error) {
        let localized = error as? any LocalizedError
        message = localized?.errorDescription ?? "Your hydration update could not be completed."
        recovery = localized?.recoverySuggestion
    }
}

@Observable
@MainActor
final class HydrationLaunchViewModel {
    private(set) var workspace: HydrationWorkspaceViewModel?
    private(set) var issue: HydrationIssue?
    private(set) var isLoading = false
    private let loader: @MainActor () async throws -> HydrationWorkspaceViewModel

    init(loader: @escaping @MainActor () async throws -> HydrationWorkspaceViewModel) { self.loader = loader }

    func open() async {
        guard workspace == nil, !isLoading else { return }
        isLoading = true
        issue = nil
        defer { isLoading = false }
        do {
            workspace = try await loader()
        } catch {
            issue = HydrationIssue(error)
        }
    }
}

@Observable
@MainActor
final class HydrationWorkspaceViewModel {
    enum Tab: Hashable { case today, history, goal, routine }
    enum Sheet: String, Identifiable { case logWater; var id: String { rawValue } }

    var selectedTab: Tab = .today
    var sheet: Sheet?
    private(set) var today = Date()
    private(set) var todayProgress: HydrationProgress?
    private(set) var todayEntries: [WaterIntakeEntry] = []
    private(set) var todayIssue: HydrationIssue?
    private(set) var isLoadingToday = false
    private(set) var todayConfirmation: String?
    private(set) var lastSavedIntakeID: UUID?
    private(set) var widgetIssue: HydrationIssue?

    var historyDate = Date()
    private(set) var history: HydrationDayHistory?
    private(set) var historyIssue: HydrationIssue?
    private(set) var isLoadingHistory = false

    var goalDate = Date()
    var goalTargetText = "2000" { didSet { goalIssue = nil; goalConfirmation = nil } }
    private(set) var goalIssue: HydrationIssue?
    private(set) var goalConfirmation: String?
    private(set) var isLoadingGoal = false

    var intakeAmountText = "250" { didSet { intakeIssue = nil } }
    var drinkingDate = Date() { didSet { intakeIssue = nil; intakeNeedsGoal = false } }
    private(set) var intakeIssue: HydrationIssue?
    private(set) var intakeNeedsGoal = false
    private(set) var isSaving = false

    var routineEnabled = false { didSet { clearRoutineFeedback() } }
    var routineStart = Date()
    var routineEnd = Date()
    var routineInterval = 60
    var routineWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    var routineIssue: HydrationIssue?
    var routineConfirmation: String?
    private(set) var notificationPermission: HydrationNotificationPermission = .notDetermined
    private(set) var scheduledReminderCount = 0
    private(set) var nextReminderDate: Date?
    private(set) var isSavingRoutine = false
    private(set) var isRefreshingReminders = false

    let calendar: Calendar
    private let repository: any HydrationRepository
    private let routineStore: any HydrationReminderRoutineStore
    private let widgetPublisher: PublishHydrationWidgetSnapshotUseCase?
    private let reminderScheduler: (any HydrationReminderScheduler)?
    private var todayRequest = UUID()
    private var historyRequest = UUID()
    private var goalRequest = UUID()

    init(
        repository: any HydrationRepository, routineStore: any HydrationReminderRoutineStore,
        calendar: Calendar = .current,
        widgetPublisher: PublishHydrationWidgetSnapshotUseCase? = nil,
        reminderScheduler: (any HydrationReminderScheduler)? = nil
    ) {
        self.repository = repository
        self.routineStore = routineStore
        self.calendar = calendar
        self.widgetPublisher = widgetPublisher
        self.reminderScheduler = reminderScheduler
        let routine: HydrationReminderRoutine
        let loadIssue: HydrationIssue?
        do {
            routine = try routineStore.load() ?? .initial
            loadIssue = nil
        } catch {
            routine = .initial
            loadIssue = HydrationIssue(error)
        }
        routineEnabled = routine.isEnabled
        routineStart = calendar.date(bySettingHour: routine.startMinute / 60, minute: routine.startMinute % 60,
                                     second: 0, of: Date()) ?? Date()
        routineEnd = calendar.date(bySettingHour: routine.endMinute / 60, minute: routine.endMinute % 60,
                                   second: 0, of: Date()) ?? Date()
        routineInterval = routine.intervalMinutes
        routineWeekdays = routine.weekdays
        // Restoring observable fields can clear feedback, so apply the load error last.
        routineIssue = loadIssue
    }

    func refreshToday() async {
        let request = UUID()
        todayRequest = request
        isLoadingToday = true
        todayIssue = nil
        defer { if request == todayRequest { isLoadingToday = false } }
        let referenceDate = Date()
        today = referenceDate
        do {
            let progress = try await FetchTodayHydrationProgressUseCase(
                repository: repository, calendar: calendar, now: { referenceDate }
            ).execute()
            let records = try await FetchHydrationHistoryUseCase(repository: repository, calendar: calendar)
                .execute(on: referenceDate)
            guard request == todayRequest, !Task.isCancelled else { return }
            todayProgress = progress
            todayEntries = records.entries
            publishWidgetSnapshot(at: referenceDate)
        } catch FetchTodayHydrationProgressUseCase.Failure.missingTodayGoal {
            guard request == todayRequest, !Task.isCancelled else { return }
            todayProgress = nil
            todayEntries = []
            publishWidgetSnapshot(at: referenceDate)
        } catch {
            guard request == todayRequest, !Task.isCancelled else { return }
            todayIssue = HydrationIssue(error)
            todayProgress = nil
            todayEntries = []
        }
    }

    private func publishWidgetSnapshot(at date: Date) {
        do {
            try widgetPublisher?.execute(progress: todayProgress, entries: todayEntries, at: date)
            widgetIssue = nil
        } catch {
            widgetIssue = HydrationIssue(error)
        }
    }

    func loadHistory() async {
        let request = UUID()
        historyRequest = request
        let date = historyDate
        history = nil
        historyIssue = nil
        isLoadingHistory = true
        defer { if request == historyRequest { isLoadingHistory = false } }
        do {
            let result = try await FetchHydrationHistoryUseCase(repository: repository, calendar: calendar)
                .execute(on: date)
            guard request == historyRequest, !Task.isCancelled else { return }
            history = result
        } catch {
            guard request == historyRequest, !Task.isCancelled else { return }
            historyIssue = HydrationIssue(error)
        }
    }

    func loadGoal() async {
        let request = UUID()
        goalRequest = request
        let date = goalDate
        isLoadingGoal = true
        goalIssue = nil
        goalConfirmation = nil
        defer { if request == goalRequest { isLoadingGoal = false } }
        do {
            let goal = try await repository.fetchGoal(on: date)
            guard request == goalRequest, !Task.isCancelled else { return }
            goalTargetText = String(goal?.targetMillilitres ?? 2_000)
        } catch {
            guard request == goalRequest, !Task.isCancelled else { return }
            goalIssue = HydrationIssue(error)
        }
    }

    func selectGoalDay(_ date: Date) {
        goalDate = date
        selectedTab = .goal
    }

    func moveHistoryDay(by value: Int) {
        guard let date = calendar.date(byAdding: .day, value: value, to: historyDate),
              calendar.startOfDay(for: date) <= calendar.startOfDay(for: Date()) else { return }
        historyDate = date
    }

    func clearRoutineFeedback() {
        routineIssue = nil
        routineConfirmation = nil
    }

    func openIntakeForm(on date: Date? = nil) {
        drinkingDate = date ?? Date()
        intakeAmountText = "250"
        intakeIssue = nil
        intakeNeedsGoal = false
        sheet = .logWater
    }

    func saveGoal() async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        goalIssue = nil
        goalConfirmation = nil
        defer { isSaving = false }
        do {
            guard let target = Int(goalTargetText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw InputFailure.invalidDailyTarget
            }
            let date = goalDate
            _ = try await UpdateDailyHydrationGoalUseCase(repository: repository, calendar: calendar)
                .execute(targetMillilitres: target, on: date)
            goalConfirmation = "Daily goal saved."
            await refreshToday()
            if calendar.isDate(historyDate, inSameDayAs: date) { await loadHistory() }
            await refreshReminderSchedule()
            return true
        } catch {
            goalIssue = HydrationIssue(error)
            return false
        }
    }

    func saveIntake() async -> Bool {
        guard let amount = Int(intakeAmountText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            intakeIssue = HydrationIssue(InputFailure.invalidWaterAmount)
            return false
        }
        return await recordIntake(amount: amount, at: drinkingDate, fromForm: true)
    }

    func quickAdd(_ amount: Int) async {
        _ = await recordIntake(amount: amount, at: Date(), fromForm: false)
    }

    private func recordIntake(amount: Int, at date: Date, fromForm: Bool) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        intakeIssue = nil
        intakeNeedsGoal = false
        todayConfirmation = nil
        defer { isSaving = false }
        do {
            let entry = try await LogWaterIntakeUseCase(repository: repository, calendar: calendar)
                .execute(amountMillilitres: amount, recordedAt: date)
            lastSavedIntakeID = entry.id
            todayConfirmation = "\(entry.amountMillilitres) mL recorded."
            await refreshToday()
            if calendar.isDate(historyDate, inSameDayAs: date) { await loadHistory() }
            await refreshReminderSchedule()
            return true
        } catch {
            if fromForm {
                intakeIssue = HydrationIssue(error)
                intakeNeedsGoal = (error as? LogWaterIntakeUseCase.Failure) == .missingDailyGoal
            } else {
                todayIssue = HydrationIssue(error)
            }
            return false
        }
    }

    func toggleWeekday(_ day: HydrationWeekday) {
        if routineWeekdays.contains(day.rawValue) { routineWeekdays.remove(day.rawValue) }
        else { routineWeekdays.insert(day.rawValue) }
        routineIssue = nil
        routineConfirmation = nil
    }

    func saveRoutine() async {
        guard !isSaving, !isSavingRoutine, !isRefreshingReminders else { return }
        isSavingRoutine = true
        defer { isSavingRoutine = false }
        routineIssue = nil
        routineConfirmation = nil
        let start = calendar.dateComponents([.hour, .minute], from: routineStart)
        let end = calendar.dateComponents([.hour, .minute], from: routineEnd)
        let routine = HydrationReminderRoutine(
            isEnabled: routineEnabled, startMinute: (start.hour ?? 0) * 60 + (start.minute ?? 0),
            endMinute: (end.hour ?? 0) * 60 + (end.minute ?? 0), intervalMinutes: routineInterval,
            weekdays: routineWeekdays
        )
        do {
            if reminderScheduler != nil {
                try await applyReminderRoutine(routine, requestPermission: true)
                routineConfirmation = routine.isEnabled ? "Reminder routine saved and scheduled." : "Water-break reminders turned off."
                await updateReminderStatus()
            } else {
                try SaveHydrationReminderRoutineUseCase(store: routineStore).execute(routine)
                routineConfirmation = "Reminder routine saved."
            }
        } catch {
            routineIssue = HydrationIssue(error)
            await updateReminderStatus()
        }
    }

    private var completedHydrationDay: Date? {
        todayProgress?.isGoalReached == true ? todayProgress?.goal.date : nil
    }

    private func applyReminderRoutine(_ routine: HydrationReminderRoutine, requestPermission: Bool) async throws {
        guard let reminderScheduler else { return }
        while true {
            let completedDay = completedHydrationDay
            _ = try await ScheduleHydrationRemindersUseCase(store: routineStore, scheduler: reminderScheduler, calendar: calendar)
                .execute(routine, at: Date(), completedDay: completedDay, requestPermission: requestPermission)
            // Intake or goal writes can finish while the system installs notification requests.
            if completedDay == completedHydrationDay { return }
        }
    }

    private func updateReminderStatus() async {
        guard let reminderScheduler else { return }
        notificationPermission = await reminderScheduler.permission()
        let pending = await reminderScheduler.pendingReminders()
        scheduledReminderCount = pending.count
        nextReminderDate = pending.first?.scheduledAt
    }

    func refreshReminderSchedule() async {
        guard reminderScheduler != nil, !isSavingRoutine, !isRefreshingReminders else { return }
        isRefreshingReminders = true
        defer { isRefreshingReminders = false }
        await updateReminderStatus()
        do {
            let saved = try routineStore.load() ?? .initial
            guard notificationPermission != .notDetermined || !saved.isEnabled else { return }
            try await applyReminderRoutine(saved, requestPermission: false)
            if routineIssue == HydrationIssue(ScheduleHydrationRemindersUseCase.Failure.notificationsNotAllowed) ||
               routineIssue == HydrationIssue(ScheduleHydrationRemindersUseCase.Failure.unableToScheduleReminders) {
                routineIssue = nil
            }
            await updateReminderStatus()
        } catch {
            routineIssue = HydrationIssue(error)
            await updateReminderStatus()
        }
    }

    func stopReminders() async {
        guard let reminderScheduler, !isSavingRoutine, !isRefreshingReminders else { return }
        isSavingRoutine = true
        defer { isSavingRoutine = false }
        clearRoutineFeedback()
        do {
            let disabled = ((try? routineStore.load()) ?? .initial).disablingReminders()
            _ = try await ScheduleHydrationRemindersUseCase(store: routineStore, scheduler: reminderScheduler, calendar: calendar)
                .execute(disabled, at: Date(), requestPermission: false)
            routineEnabled = false
            await updateReminderStatus()
            routineConfirmation = "Water-break reminders turned off."
        } catch { routineIssue = HydrationIssue(error) }
        await updateReminderStatus()
    }

    func sendReminderPreview() async {
        guard let reminderScheduler, !isSavingRoutine, !isRefreshingReminders else { return }
        isSavingRoutine = true
        defer { isSavingRoutine = false }
        clearRoutineFeedback()
        do {
            try await SendHydrationReminderPreviewUseCase(scheduler: reminderScheduler).execute()
            routineConfirmation = "Test water-break reminder scheduled for 5 seconds from now."
        } catch { routineIssue = HydrationIssue(error) }
    }

    enum InputFailure: LocalizedError {
        case invalidWaterAmount, invalidDailyTarget

        var errorDescription: String? {
            switch self {
            case .invalidWaterAmount: "Enter the water amount as a whole number of millilitres."
            case .invalidDailyTarget: "Enter your daily target as a whole number of millilitres."
            }
        }

        var recoverySuggestion: String? { "Use digits only, then try saving again." }
    }
}
