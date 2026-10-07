import WidgetKit

struct WidgetReloadingHydrationSnapshotStore: HydrationWidgetSnapshotStore {
    private let store: any HydrationWidgetSnapshotStore
    private let reloadTimeline: @Sendable () -> Void

    init(
        store: any HydrationWidgetSnapshotStore,
        reloadTimeline: @escaping @Sendable () -> Void = {
            WidgetCenter.shared.reloadTimelines(ofKind: HydrationWidgetIdentity.kind)
        }
    ) {
        self.store = store
        self.reloadTimeline = reloadTimeline
    }

    func load() throws -> HydrationWidgetSnapshot? { try store.load() }

    func save(_ snapshot: HydrationWidgetSnapshot) throws {
        let previous = try? store.load()
        try store.save(snapshot)
        // A refresh-only timestamp change does not alter widget content or need another timeline request.
        if previous?.dayStart != snapshot.dayStart || previous?.dayEnd != snapshot.dayEnd ||
            previous?.timeZoneIdentifier != snapshot.timeZoneIdentifier ||
            previous?.targetMillilitres != snapshot.targetMillilitres ||
            previous?.consumedMillilitres != snapshot.consumedMillilitres ||
            previous?.lastIntakeAt != snapshot.lastIntakeAt {
            reloadTimeline()
        }
    }
}
