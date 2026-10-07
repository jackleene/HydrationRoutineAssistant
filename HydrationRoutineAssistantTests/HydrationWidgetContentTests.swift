import Foundation
import Testing
@testable import HydrationRoutineAssistant

struct HydrationWidgetContentTests {
    private let date = Date(timeIntervalSince1970: 1_791_374_400)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func snapshot(target: Int? = 2_000, consumed: Int = 250, at date: Date? = nil) throws -> HydrationWidgetSnapshot {
        let date = date ?? self.date
        return try HydrationWidgetSnapshot(
            day: try #require(calendar.dateInterval(of: .day, for: date)),
            timeZoneIdentifier: calendar.timeZone.identifier, targetMillilitres: target,
            consumedMillilitres: consumed, lastIntakeAt: nil, updatedAt: date
        )
    }

    @Test("The widget reads current progress from its shared snapshot")
    func currentProgressIsDisplayed() throws {
        let expected = try snapshot()
        let store = WidgetStoreProbe(snapshot: expected)
        #expect(HydrationWidgetContent.read(from: store, at: date, calendar: calendar) == .progress(expected))
    }

    @Test("A shared day with no goal asks the stakeholder to set a daily target")
    func absentGoalOffersSetup() throws {
        let store = WidgetStoreProbe(snapshot: try snapshot(target: nil, consumed: 0))
        #expect(HydrationWidgetContent.read(from: store, at: date, calendar: calendar) == .needsGoal)
    }

    @Test("Missing or expired widget progress asks for today's refresh")
    func missingAndExpiredProgressAreNotDisplayed() throws {
        let empty = WidgetStoreProbe()
        #expect(HydrationWidgetContent.read(from: empty, at: date, calendar: calendar) == .needsRefresh)
        let old = try snapshot()
        let store = WidgetStoreProbe(snapshot: old)
        #expect(HydrationWidgetContent.read(from: store, at: old.dayEnd, calendar: calendar) == .needsRefresh)
    }

    @Test("Unreadable shared storage becomes a recoverable widget state")
    func unreadableStoreShowsRecovery() {
        let store = AppGroupHydrationWidgetSnapshotStore(containerURL: nil)
        #expect(HydrationWidgetContent.read(from: store, at: date, calendar: calendar) == .unavailable)
        #expect(HydrationWidgetContent.unavailable.guidance == "Open the app to refresh your saved progress.")
    }

    @Test("Changed intake and goals request reloads only after the snapshot is saved")
    func relevantChangesReloadTimeline() throws {
        let probe = WidgetStoreProbe()
        let store = WidgetReloadingHydrationSnapshotStore(store: probe, reloadTimeline: { probe.recordReload() })

        try store.save(snapshot())
        #expect(probe.reloadCount == 1)
        #expect(probe.snapshotSeenOnReload?.consumedMillilitres == 250)

        try store.save(snapshot(at: date.addingTimeInterval(1)))
        #expect(probe.reloadCount == 1)

        try store.save(snapshot(target: 2_500))
        #expect(probe.reloadCount == 2)
        #expect(probe.snapshotSeenOnReload?.targetMillilitres == 2_500)

        try store.save(snapshot(target: 2_500, consumed: 500))
        #expect(probe.reloadCount == 3)
        #expect(probe.snapshotSeenOnReload?.consumedMillilitres == 500)
    }

    @Test("Failed snapshot writes never request a misleading widget reload")
    func failedWriteDoesNotReload() throws {
        let probe = WidgetStoreProbe(failsSave: true)
        let store = WidgetReloadingHydrationSnapshotStore(store: probe, reloadTimeline: { probe.recordReload() })

        #expect(throws: HydrationWidgetStoreError.unableToSaveSnapshot) { try store.save(snapshot()) }

        #expect(probe.reloadCount == 0)
        #expect(probe.snapshotSeenOnReload == nil)
    }

    @Test("Only the intended widget URL opens today's hydration workflow", arguments: [
        (url: "hydrationroutine://today", allowed: true),
        (url: "https://today", allowed: false),
        (url: "hydrationroutine://history", allowed: false),
        (url: "hydrationroutine://today/other", allowed: false),
        (url: "hydrationroutine://today?amount=500", allowed: false)
    ])
    func widgetURLUsesExpectedRoute(_ input: (url: String, allowed: Bool)) throws {
        let url = try #require(URL(string: input.url))
        #expect(HydrationWidgetIdentity.opensToday(url) == input.allowed)
    }
}

private final class WidgetStoreProbe: HydrationWidgetSnapshotStore, @unchecked Sendable {
    private let lock = NSLock()
    private let failsSave: Bool
    private var storedSnapshot: HydrationWidgetSnapshot?
    private var reloads = 0
    private var reloadedSnapshot: HydrationWidgetSnapshot?

    init(snapshot: HydrationWidgetSnapshot? = nil, failsSave: Bool = false) {
        storedSnapshot = snapshot
        self.failsSave = failsSave
    }

    var reloadCount: Int { lock.withLock { reloads } }
    var snapshotSeenOnReload: HydrationWidgetSnapshot? { lock.withLock { reloadedSnapshot } }
    func load() throws -> HydrationWidgetSnapshot? { lock.withLock { storedSnapshot } }
    func save(_ snapshot: HydrationWidgetSnapshot) throws {
        if failsSave { throw HydrationWidgetStoreError.unableToSaveSnapshot }
        lock.withLock { storedSnapshot = snapshot }
    }
    func recordReload() {
        lock.withLock {
            reloads += 1
            reloadedSnapshot = storedSnapshot
        }
    }
}
