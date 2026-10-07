import Foundation

struct PublishHydrationWidgetSnapshotUseCase: Sendable {
    private let store: any HydrationWidgetSnapshotStore
    private let calendar: Calendar

    init(store: any HydrationWidgetSnapshotStore, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    func execute(progress: HydrationProgress?, entries: [WaterIntakeEntry], at date: Date) throws {
        guard let day = calendar.dateInterval(of: .day, for: date) else { throw Failure.invalidHydrationDay }
        if let progress {
            guard calendar.isDate(progress.goal.date, inSameDayAs: date) else { throw Failure.goalDayMismatch }
        }
        let lastIntake = entries.filter {
            $0.goalID == progress?.goal.id && calendar.isDate($0.recordedAt, inSameDayAs: date) && $0.recordedAt <= date
        }.map(\.recordedAt).max()
        let snapshot: HydrationWidgetSnapshot
        do {
            snapshot = try HydrationWidgetSnapshot(
                day: day, timeZoneIdentifier: calendar.timeZone.identifier,
                targetMillilitres: progress?.goal.targetMillilitres,
                consumedMillilitres: progress?.consumedMillilitres ?? 0,
                lastIntakeAt: lastIntake, updatedAt: date
            )
        } catch {
            throw Failure.invalidHydrationDay
        }
        do { try store.save(snapshot) }
        catch { throw Failure.unableToShareProgress }
    }

    enum Failure: LocalizedError, Equatable {
        case invalidHydrationDay
        case goalDayMismatch
        case unableToShareProgress

        var errorDescription: String? {
            switch self {
            case .invalidHydrationDay: "The widget's hydration day could not be determined."
            case .goalDayMismatch: "The drinking progress belongs to a different day than the widget update."
            case .unableToShareProgress: "Your drinking progress could not be shared with the widget."
            }
        }

        var recoverySuggestion: String? {
            "Your drinking records remain in the app. Return to Today and refresh to retry the widget update."
        }
    }
}
