import CoreData
import Foundation
import UserNotifications

@MainActor
final class UserDefaultsHydrationReminderRoutineStore: HydrationReminderRoutineStore {
    private let defaults: UserDefaults
    private let key = "hydration.reminderRoutine.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() throws -> HydrationReminderRoutine? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            let routine = try JSONDecoder().decode(HydrationReminderRoutine.self, from: data)
            try routine.validate()
            return routine
        } catch {
            throw HydrationRoutineStoreError.unreadablePreferences
        }
    }

    func save(_ routine: HydrationReminderRoutine) throws {
        do {
            let data = try JSONEncoder().encode(routine)
            defaults.set(data, forKey: key)
        } catch {
            throw HydrationRoutineStoreError.saveFailed
        }
    }
}

enum HydrationComposition {
    @MainActor
    static func makeWorkspace() async throws -> HydrationWorkspaceViewModel {
        let calendar = Calendar.autoupdatingCurrent
        let container = try await HydrationPersistence.makeContainer()
        let repository = CoreDataHydrationRepository(container: container, calendar: calendar)
        let scheduler = UserNotificationHydrationReminderScheduler()
        let workspace = HydrationWorkspaceViewModel(
            repository: repository, routineStore: UserDefaultsHydrationReminderRoutineStore(), calendar: calendar,
            widgetPublisher: PublishHydrationWidgetSnapshotUseCase(
                store: WidgetReloadingHydrationSnapshotStore(store: AppGroupHydrationWidgetSnapshotStore()),
                calendar: calendar
            ), reminderScheduler: scheduler
        )
        scheduler.onOpenToday = { [weak workspace] in
            guard let workspace else { return }
            workspace.selectedTab = .today
            workspace.sheet = nil
            Task { await workspace.refreshToday() }
        }
        return workspace
    }
}

@MainActor
final class UserNotificationHydrationReminderScheduler: NSObject, HydrationReminderScheduler, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter
    var onOpenToday: (@MainActor () -> Void)?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
        let action = UNNotificationAction(identifier: HydrationNotificationIdentity.openTodayAction,
                                          title: "Open today's water intake", options: .foreground)
        center.setNotificationCategories([
            UNNotificationCategory(identifier: HydrationNotificationIdentity.category,
                                   actions: [action], intentIdentifiers: [], options: [])
        ])
    }

    func permission() async -> HydrationNotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .authorized
        case .notDetermined: .notDetermined
        case .denied: .denied
        @unknown default: .denied
        }
    }

    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func replaceReminders(with reminders: [HydrationReminder], calendar: Calendar) async throws {
        let previous = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(HydrationNotificationIdentity.requestPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: previous.map(\.identifier))
        do {
            for reminder in reminders {
                var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.scheduledAt)
                components.calendar = calendar
                components.timeZone = calendar.timeZone
                let content = makeContent()
                content.userInfo = [HydrationNotificationIdentity.scheduledAtKey: reminder.scheduledAt.timeIntervalSince1970]
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
            }
        } catch {
            // Remove partial additions so a failed update cannot leave a misleading half-applied routine.
            center.removePendingNotificationRequests(withIdentifiers: reminders.map(\.id))
            throw error
        }
    }

    func pendingReminders() async -> [HydrationReminder] {
        await center.pendingNotificationRequests().compactMap { request in
            guard request.identifier.hasPrefix(HydrationNotificationIdentity.requestPrefix),
                  let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let date = trigger.nextTriggerDate() else { return nil }
            return HydrationReminder(scheduledAt: date)
        }.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    func sendPreview() async throws {
        let content = makeContent()
        content.title = "Test water break"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try await center.add(UNNotificationRequest(
            identifier: HydrationNotificationIdentity.previewIdentifier, content: content, trigger: trigger
        ))
    }

    private func makeContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Time for a water break"
        content.body = "Pause for water when it suits your routine. Open the app to record your drink and check today's goal."
        content.categoryIdentifier = HydrationNotificationIdentity.category
        content.sound = .default
        return content
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        notification.request.identifier.hasPrefix(HydrationNotificationIdentity.requestPrefix) ? [.banner, .sound] : []
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let requestIdentifier = response.notification.request.identifier
        let actionIdentifier = response.actionIdentifier
        // UIKit can restore its scene when this callback completes, so finish on the main thread.
        Task { @MainActor in
            HydrationNotificationResponseHandler.handle(
                requestIdentifier: requestIdentifier,
                actionIdentifier: actionIdentifier,
                onOpenToday: { [weak self] in self?.onOpenToday?() },
                completionHandler: completionHandler
            )
        }
    }
}

@MainActor
enum HydrationNotificationResponseHandler {
    static func handle(
        requestIdentifier: String,
        actionIdentifier: String,
        onOpenToday: @MainActor @Sendable () -> Void,
        completionHandler: @Sendable () -> Void
    ) {
        let opensToday = requestIdentifier.hasPrefix(HydrationNotificationIdentity.requestPrefix) &&
            (actionIdentifier == UNNotificationDefaultActionIdentifier ||
             actionIdentifier == HydrationNotificationIdentity.openTodayAction)
        if opensToday { onOpenToday() }
        completionHandler()
    }
}

#if DEBUG
actor HydrationPreviewRepository: HydrationRepository {
    private var goals: [HydrationGoal] = []
    private var entries: [WaterIntakeEntry] = []

    func fetchGoal(on date: Date) async throws -> HydrationGoal? {
        goals.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func saveGoal(_ goal: HydrationGoal) async throws {
        goals.removeAll { $0.id == goal.id }
        goals.append(goal)
    }

    func fetchIntakes(for goalID: UUID, on date: Date) async throws -> [WaterIntakeEntry] {
        entries.filter { $0.goalID == goalID && Calendar.current.isDate($0.recordedAt, inSameDayAs: date) }
    }

    func saveIntake(_ entry: WaterIntakeEntry) async throws { entries.append(entry) }
}

@MainActor
final class HydrationPreviewRoutineStore: HydrationReminderRoutineStore {
    private var routine: HydrationReminderRoutine?
    func load() throws -> HydrationReminderRoutine? { routine }
    func save(_ routine: HydrationReminderRoutine) throws { self.routine = routine }
}
#endif
