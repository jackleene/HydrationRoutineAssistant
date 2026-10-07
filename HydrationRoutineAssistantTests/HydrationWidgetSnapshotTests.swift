import Foundation
import Testing
@testable import HydrationRoutineAssistant

struct HydrationWidgetSnapshotTests {
    private let date = Date(timeIntervalSince1970: 1_791_374_400)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func snapshot() throws -> HydrationWidgetSnapshot {
        try HydrationWidgetSnapshot(
            day: try #require(calendar.dateInterval(of: .day, for: date)),
            timeZoneIdentifier: calendar.timeZone.identifier, targetMillilitres: 2_000,
            consumedMillilitres: 250, lastIntakeAt: date, updatedAt: date
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("Widget progress survives reopening the shared snapshot store")
    func storedSnapshotSurvivesReopening() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstStore = AppGroupHydrationWidgetSnapshotStore(containerURL: directory)
        let expected = try snapshot()

        try firstStore.save(expected)
        let secondStore = AppGroupHydrationWidgetSnapshotStore(containerURL: directory)

        #expect(try secondStore.load() == expected)
        #expect(expected.remainingMillilitres == 1_750)
        #expect(expected.completionFraction == 0.125)
    }

    @Test("A shared container without a snapshot is a valid first-launch empty state")
    func missingSnapshotIsEmpty() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(try AppGroupHydrationWidgetSnapshotStore(containerURL: directory).load() == nil)
    }

    @Test("Corrupt snapshots are rejected instead of showing misleading intake")
    func unreadableSnapshotIsRejected() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not a hydration snapshot".utf8)
            .write(to: directory.appendingPathComponent(HydrationSharedContainer.snapshotFilename))

        #expect(throws: HydrationWidgetStoreError.unreadableSnapshot) {
            try AppGroupHydrationWidgetSnapshotStore(containerURL: directory).load()
        }
    }

    @Test("Decoded snapshots reject unsupported versions and invalid totals", arguments: [
        (field: "schemaVersion", value: 2), (field: "consumedMillilitres", value: -1)
    ])
    func decodedSnapshotIsValidated(_ input: (field: String, value: Int)) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let encoded = try JSONEncoder().encode(snapshot())
        var fields = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        fields[input.field] = input.value
        let data = try JSONSerialization.data(withJSONObject: fields)
        try data.write(to: directory.appendingPathComponent(HydrationSharedContainer.snapshotFilename))

        #expect(throws: HydrationWidgetStoreError.unreadableSnapshot) {
            try AppGroupHydrationWidgetSnapshotStore(containerURL: directory).load()
        }
    }

    @Test("Snapshot freshness excludes tomorrow and a changed time zone")
    func snapshotExpiresAtDayBoundary() throws {
        let snapshot = try snapshot()
        #expect(snapshot.isCurrent(at: snapshot.dayStart, calendar: calendar))
        #expect(snapshot.isCurrent(at: snapshot.dayEnd.addingTimeInterval(-1), calendar: calendar))
        #expect(!snapshot.isCurrent(at: snapshot.dayEnd, calendar: calendar))
        #expect(!snapshot.isCurrent(at: snapshot.dayStart.addingTimeInterval(-1), calendar: calendar))
        var changedCalendar = calendar
        changedCalendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        #expect(!snapshot.isCurrent(at: date, calendar: changedCalendar))
    }

    @Test("Shared snapshots respect Sydney's daylight-saving day lengths", arguments: [
        (month: 4, day: 5, hours: 25.0), (month: 10, day: 4, hours: 23.0)
    ])
    func snapshotUsesCalendarDay(_ input: (month: Int, day: Int, hours: Double)) throws {
        var calendar = calendar
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: input.month, day: input.day, hour: 12)))
        let store = SnapshotMemoryStore()

        try PublishHydrationWidgetSnapshotUseCase(store: store, calendar: calendar)
            .execute(progress: nil, entries: [], at: date)

        let snapshot = try #require(store.snapshot)
        #expect(snapshot.dayEnd.timeIntervalSince(snapshot.dayStart) == input.hours * 3_600)
        #expect(snapshot.isCurrent(at: date, calendar: calendar))
    }

    @Test("Publishing shares matching-day totals while preserving amounts above the goal")
    func publishingPreservesDailyProgress() throws {
        let goal = try HydrationGoal(date: date, targetMillilitres: 500)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: date))
        let earlier = date.addingTimeInterval(-60)
        let entries = try [
            WaterIntakeEntry(goalID: goal.id, amountMillilitres: 500, recordedAt: earlier, now: date),
            WaterIntakeEntry(goalID: goal.id, amountMillilitres: 250, recordedAt: date, now: date),
            WaterIntakeEntry(goalID: goal.id, amountMillilitres: 500, recordedAt: yesterday, now: date),
            WaterIntakeEntry(goalID: UUID(), amountMillilitres: 500, recordedAt: date, now: date)
        ]
        let progress = HydrationProgress(goal: goal, entries: entries, calendar: calendar)
        let store = SnapshotMemoryStore()

        try PublishHydrationWidgetSnapshotUseCase(store: store, calendar: calendar)
            .execute(progress: progress, entries: entries, at: date)

        let snapshot = try #require(store.snapshot)
        #expect(snapshot.targetMillilitres == 500)
        #expect(snapshot.consumedMillilitres == 750)
        #expect(snapshot.remainingMillilitres == 0)
        #expect(snapshot.completionFraction == 1)
        #expect(snapshot.lastIntakeAt == date)
        #expect(snapshot.updatedAt == date)
    }

    @Test("A day without a goal replaces previous progress with an explicit empty snapshot")
    func emptyDayReplacesPreviousSnapshot() throws {
        let store = SnapshotMemoryStore()
        try store.save(snapshot())

        try PublishHydrationWidgetSnapshotUseCase(store: store, calendar: calendar)
            .execute(progress: nil, entries: [], at: date)

        let snapshot = try #require(store.snapshot)
        #expect(snapshot.targetMillilitres == nil)
        #expect(snapshot.consumedMillilitres == 0)
        #expect(snapshot.lastIntakeAt == nil)
        #expect(snapshot.remainingMillilitres == nil)
    }

    @Test("A previous day's goal cannot overwrite today's widget progress")
    func wrongDayDoesNotPublish() throws {
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: date))
        let goal = try HydrationGoal(date: yesterday, targetMillilitres: 2_000)
        let store = SnapshotMemoryStore()
        let progress = HydrationProgress(goal: goal, entries: [], calendar: calendar)

        #expect(throws: PublishHydrationWidgetSnapshotUseCase.Failure.goalDayMismatch) {
            try PublishHydrationWidgetSnapshotUseCase(store: store, calendar: calendar)
                .execute(progress: progress, entries: [], at: date)
        }
        #expect(store.snapshot == nil)
    }

    @Test("Unavailable shared storage produces a recoverable domain error")
    func unavailableStoreUsesDomainError() {
        let store = AppGroupHydrationWidgetSnapshotStore(containerURL: nil)
        #expect(throws: HydrationWidgetStoreError.sharedContainerUnavailable) { try store.load() }
        #expect(throws: PublishHydrationWidgetSnapshotUseCase.Failure.unableToShareProgress) {
            try PublishHydrationWidgetSnapshotUseCase(store: store, calendar: calendar)
                .execute(progress: nil, entries: [], at: date)
        }
    }

    @Test("Saving water and editing a goal update shared progress without direct database access")
    @MainActor
    func intakeSavePublishesSnapshot() async throws {
        let now = Date()
        let goal = try HydrationGoal(date: now, targetMillilitres: 2_000)
        let store = SnapshotMemoryStore()
        let repository = MockHydrationRepository(goal: goal)
        let model = HydrationWorkspaceViewModel(
            repository: repository, routineStore: SnapshotRoutineStore(), calendar: calendar,
            widgetPublisher: PublishHydrationWidgetSnapshotUseCase(store: store, calendar: calendar)
        )
        model.drinkingDate = now

        let saved = await model.saveIntake()

        #expect(saved)
        #expect(store.snapshot?.consumedMillilitres == 250)
        #expect(store.snapshot?.targetMillilitres == 2_000)
        #expect(model.widgetIssue == nil)
        #expect(await repository.savedIntakes.count == 1)
        model.goalDate = now
        model.goalTargetText = "2500"

        let goalSaved = await model.saveGoal()

        #expect(goalSaved)
        #expect(store.snapshot?.targetMillilitres == 2_500)
        #expect(store.snapshot?.consumedMillilitres == 250)
        #expect(model.widgetIssue == nil)
    }

    @Test("A failed widget update does not report a saved drink as a failed intake")
    @MainActor
    func sharingFailureDoesNotUndoIntake() async throws {
        let now = Date()
        let goal = try HydrationGoal(date: now, targetMillilitres: 2_000)
        let repository = MockHydrationRepository(goal: goal)
        let model = HydrationWorkspaceViewModel(
            repository: repository, routineStore: SnapshotRoutineStore(), calendar: calendar,
            widgetPublisher: PublishHydrationWidgetSnapshotUseCase(
                store: AppGroupHydrationWidgetSnapshotStore(containerURL: nil), calendar: calendar
            )
        )
        model.drinkingDate = now

        let saved = await model.saveIntake()

        #expect(saved)
        #expect(await repository.savedIntakes.count == 1)
        #expect(model.todayProgress?.consumedMillilitres == 250)
        #expect(model.intakeIssue == nil)
        #expect(model.widgetIssue == HydrationIssue(PublishHydrationWidgetSnapshotUseCase.Failure.unableToShareProgress))
        #expect(model.todayConfirmation == "250 mL recorded.")
    }
}

private final class SnapshotMemoryStore: HydrationWidgetSnapshotStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedSnapshot: HydrationWidgetSnapshot?

    var snapshot: HydrationWidgetSnapshot? { lock.withLock { storedSnapshot } }
    func load() throws -> HydrationWidgetSnapshot? { snapshot }
    func save(_ snapshot: HydrationWidgetSnapshot) throws { lock.withLock { storedSnapshot = snapshot } }
}

@MainActor
private final class SnapshotRoutineStore: HydrationReminderRoutineStore {
    func load() throws -> HydrationReminderRoutine? { nil }
    func save(_ routine: HydrationReminderRoutine) throws {}
}
