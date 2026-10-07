import CoreData
import Foundation
import Testing
@testable import HydrationRoutineAssistant

@MainActor
struct HydrationWorkflowIntegrationTests {
    @Test("Saved water, shared extension progress and routine preferences survive reopening")
    func savedWorkflowSurvivesReopening() async throws {
        let fixture = try WorkflowIntegrationFixture()
        defer { fixture.cleanUp() }
        let repository = try await fixture.makeRepository()
        let goal = try await UpdateDailyHydrationGoalUseCase(repository: repository, calendar: fixture.calendar)
            .execute(targetMillilitres: 2_000, on: fixture.date)
        let entry = try await LogWaterIntakeUseCase(
            repository: repository, calendar: fixture.calendar, now: { fixture.date }
        ).execute(amountMillilitres: 250, recordedAt: fixture.date)
        let progress = try await fixture.fetchProgress(from: repository)
        let publisher = fixture.makePublisher()
        try publisher.execute(progress: progress, entries: [entry], at: fixture.date)

        let preferences = UserDefaultsHydrationReminderRoutineStore(defaults: fixture.defaults)
        let scheduler = IntegrationReminderScheduler()
        let routine = fixture.routine
        let reminders = try await ScheduleHydrationRemindersUseCase(
            store: preferences, scheduler: scheduler, calendar: fixture.calendar
        ).execute(routine, at: fixture.date)
        #expect(reminders.count == 36)
        #expect(scheduler.pending == reminders)
        #expect(scheduler.permissionRequests == 0)

        fixture.closeStores()
        let reopened = try await fixture.makeRepository()
        let restoredProgress = try await fixture.fetchProgress(from: reopened)
        let restoredEntries = try await reopened.fetchIntakes(for: goal.id, on: fixture.date)
        let restoredPreferences = UserDefaultsHydrationReminderRoutineStore(defaults: fixture.defaults)
        let snapshot = try #require(try fixture.snapshotStore.load())

        #expect(restoredProgress == progress)
        #expect(restoredEntries == [entry])
        #expect(try restoredPreferences.load() == routine)
        #expect(snapshot.targetMillilitres == 2_000)
        #expect(snapshot.consumedMillilitres == 250)
        #expect(snapshot.remainingMillilitres == 1_750)
        #expect(snapshot.lastIntakeAt == entry.recordedAt)
        #expect(HydrationWidgetContent.read(from: fixture.snapshotStore, at: fixture.date,
                                          calendar: fixture.calendar) == .progress(snapshot))
        #expect(HydrationNotificationPresentation.read(from: fixture.snapshotStore, at: fixture.date,
                                                     calendar: fixture.calendar).content == .progress(snapshot))
        #expect(fixture.reloads.snapshots == [snapshot])
    }

    @Test("Completing and raising a saved goal updates both extensions and today's reminder plan")
    func goalChangesReconcileExtensionProgressAndReminders() async throws {
        let fixture = try WorkflowIntegrationFixture()
        defer { fixture.cleanUp() }
        let repository = try await fixture.makeRepository()
        let goals = UpdateDailyHydrationGoalUseCase(repository: repository, calendar: fixture.calendar)
        let goal = try await goals.execute(targetMillilitres: 500, on: fixture.date)
        let entry = try await LogWaterIntakeUseCase(
            repository: repository, calendar: fixture.calendar, now: { fixture.date }
        ).execute(amountMillilitres: 500, recordedAt: fixture.date)
        let publisher = fixture.makePublisher()
        let scheduler = IntegrationReminderScheduler()
        let schedule = ScheduleHydrationRemindersUseCase(
            store: UserDefaultsHydrationReminderRoutineStore(defaults: fixture.defaults),
            scheduler: scheduler, calendar: fixture.calendar
        )
        _ = try await schedule.execute(fixture.routine, at: fixture.date)
        try #require(scheduler.pending.contains {
            fixture.calendar.isDate($0.scheduledAt, inSameDayAs: fixture.date)
        })

        let complete = try await fixture.fetchProgress(from: repository)
        try publisher.execute(progress: complete, entries: [entry], at: fixture.date)
        _ = try await schedule.execute(fixture.routine, at: fixture.date, completedDay: complete.goal.date)
        let completedSnapshot = try #require(try fixture.snapshotStore.load())
        #expect(complete.isGoalReached)
        #expect(scheduler.pending.count == 32)
        #expect(scheduler.pending.allSatisfy {
            !fixture.calendar.isDate($0.scheduledAt, inSameDayAs: fixture.date)
        })
        #expect(completedSnapshot.remainingMillilitres == 0)
        #expect(HydrationNotificationPresentation.read(from: fixture.snapshotStore, at: fixture.date,
                                                     calendar: fixture.calendar).title == "Daily goal complete")

        let raised = try await goals.execute(targetMillilitres: 1_000, on: fixture.date)
        let progress = try await fixture.fetchProgress(from: repository)
        try publisher.execute(progress: progress, entries: [entry], at: fixture.date)
        _ = try await schedule.execute(fixture.routine, at: fixture.date)
        let updatedSnapshot = try #require(try fixture.snapshotStore.load())

        #expect(raised.id == goal.id)
        #expect(try await repository.fetchIntakes(for: goal.id, on: fixture.date) == [entry])
        #expect(!progress.isGoalReached)
        #expect(updatedSnapshot.consumedMillilitres == 500)
        #expect(updatedSnapshot.targetMillilitres == 1_000)
        #expect(updatedSnapshot.remainingMillilitres == 500)
        #expect(HydrationWidgetContent.read(from: fixture.snapshotStore, at: fixture.date,
                                          calendar: fixture.calendar) == .progress(updatedSnapshot))
        #expect(HydrationNotificationPresentation.read(from: fixture.snapshotStore, at: fixture.date,
                                                     calendar: fixture.calendar).title == "Water-break check-in")
        #expect(scheduler.pending.count == 36)
        #expect(scheduler.pending.contains {
            fixture.calendar.isDate($0.scheduledAt, inSameDayAs: fixture.date)
        })
        #expect(fixture.reloads.snapshots == [completedSnapshot, updatedSnapshot])
    }

    @Test("Retrying a failed shared-file write publishes persisted water without another intake")
    func sharingRecoveryDoesNotDuplicateSavedWater() async throws {
        let fixture = try WorkflowIntegrationFixture()
        defer { fixture.cleanUp() }
        let repository = try await fixture.makeRepository()
        let goal = try await UpdateDailyHydrationGoalUseCase(repository: repository, calendar: fixture.calendar)
            .execute(targetMillilitres: 2_000, on: fixture.date)
        let entry = try await LogWaterIntakeUseCase(
            repository: repository, calendar: fixture.calendar, now: { fixture.date }
        ).execute(amountMillilitres: 250, recordedAt: fixture.date)
        let progress = try await fixture.fetchProgress(from: repository)
        let publisher = fixture.makePublisher()
        // A file in place of the shared directory forces a real write failure without changing device permissions.
        try Data().write(to: fixture.sharedDirectory)

        #expect(throws: PublishHydrationWidgetSnapshotUseCase.Failure.unableToShareProgress) {
            try publisher.execute(progress: progress, entries: [entry], at: fixture.date)
        }
        #expect(fixture.reloads.snapshots.isEmpty)
        #expect(try await repository.fetchIntakes(for: goal.id, on: fixture.date) == [entry])
        #expect(HydrationNotificationPresentation.read(from: fixture.snapshotStore, at: fixture.date,
                                                     calendar: fixture.calendar).content == .unavailable)

        try FileManager.default.removeItem(at: fixture.sharedDirectory)
        fixture.closeStores()
        let reopened = try await fixture.makeRepository()
        let restoredProgress = try await fixture.fetchProgress(from: reopened)
        let entries = try await reopened.fetchIntakes(for: goal.id, on: fixture.date)
        try publisher.execute(progress: restoredProgress, entries: entries, at: fixture.date)
        let snapshot = try #require(try fixture.snapshotStore.load())

        #expect(entries == [entry])
        #expect(snapshot.consumedMillilitres == 250)
        #expect(snapshot.remainingMillilitres == 1_750)
        #expect(HydrationWidgetContent.read(from: fixture.snapshotStore, at: fixture.date,
                                          calendar: fixture.calendar) == .progress(snapshot))
        #expect(HydrationNotificationPresentation.read(from: fixture.snapshotStore, at: fixture.date,
                                                     calendar: fixture.calendar).content == .progress(snapshot))
        #expect(fixture.reloads.snapshots == [snapshot])

        try publisher.execute(progress: restoredProgress, entries: entries,
                              at: fixture.date.addingTimeInterval(60))
        #expect(fixture.reloads.snapshots.count == 1)
        #expect(try await reopened.fetchIntakes(for: goal.id, on: fixture.date).count == 1)
    }
}

@MainActor
private final class WorkflowIntegrationFixture {
    let date = Date(timeIntervalSince1970: 1_791_374_400)
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("HydrationWorkflowIntegration-\(UUID())", isDirectory: true)
    let suiteName = "HydrationWorkflowIntegration.\(UUID())"
    let defaults: UserDefaults
    let reloads = IntegrationWidgetReloadRecorder()
    private var containers: [NSPersistentContainer] = []

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    var sharedDirectory: URL { directory.appendingPathComponent("Shared", isDirectory: true) }
    var snapshotStore: AppGroupHydrationWidgetSnapshotStore {
        AppGroupHydrationWidgetSnapshotStore(containerURL: sharedDirectory)
    }
    var routine: HydrationReminderRoutine {
        HydrationReminderRoutine(isEnabled: true, startMinute: 540, endMinute: 1_020,
                                 intervalMinutes: 60, weekdays: [2, 3, 4, 5, 6])
    }

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    func makeRepository() async throws -> CoreDataHydrationRepository {
        let container = try await HydrationPersistence.makeContainer(
            storeURL: directory.appendingPathComponent("Hydration.sqlite")
        )
        containers.append(container)
        return CoreDataHydrationRepository(container: container, calendar: calendar)
    }

    func fetchProgress(from repository: CoreDataHydrationRepository) async throws -> HydrationProgress {
        let referenceDate = date
        return try await FetchTodayHydrationProgressUseCase(
            repository: repository, calendar: calendar, now: { referenceDate }
        ).execute()
    }

    func makePublisher() -> PublishHydrationWidgetSnapshotUseCase {
        let store = snapshotStore
        let recorder = reloads
        return PublishHydrationWidgetSnapshotUseCase(
            store: WidgetReloadingHydrationSnapshotStore(store: store, reloadTimeline: {
                recorder.record(from: store)
            }), calendar: calendar
        )
    }

    func closeStores() {
        for container in containers {
            let coordinator = container.persistentStoreCoordinator
            for store in coordinator.persistentStores { try? coordinator.remove(store) }
        }
        containers.removeAll()
    }

    func cleanUp() {
        closeStores()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

// Reload closures are Sendable, so the lock protects observations without requiring a particular executor.
private final class IntegrationWidgetReloadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var observedSnapshots: [HydrationWidgetSnapshot?] = []

    var snapshots: [HydrationWidgetSnapshot?] { lock.withLock { observedSnapshots } }
    func record(from store: any HydrationWidgetSnapshotStore) {
        let snapshot = try? store.load()
        lock.withLock { observedSnapshots.append(snapshot) }
    }
}

@MainActor
private final class IntegrationReminderScheduler: HydrationReminderScheduler {
    private(set) var pending: [HydrationReminder] = []
    private(set) var permissionRequests = 0
    func permission() async -> HydrationNotificationPermission { .authorized }
    func requestPermission() async throws -> Bool { permissionRequests += 1; return true }
    func replaceReminders(with reminders: [HydrationReminder], calendar: Calendar) async throws { pending = reminders }
    func pendingReminders() async -> [HydrationReminder] { pending }
    func sendPreview() async throws {}
}
