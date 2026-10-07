import Foundation

enum HydrationWidgetIdentity {
    static let kind = "HydrationWidget"
    static let todayURL = URL(string: "hydrationroutine://today")!

    static func opensToday(_ url: URL) -> Bool {
        url.scheme == todayURL.scheme && url.host == todayURL.host &&
        url.path.isEmpty && url.query == nil && url.fragment == nil
    }
}

enum HydrationWidgetContent: Equatable, Sendable {
    case progress(HydrationWidgetSnapshot)
    case needsGoal
    case needsRefresh
    case unavailable

    static func read(from store: any HydrationWidgetSnapshotStore, at date: Date, calendar: Calendar) -> Self {
        do {
            guard let snapshot = try store.load(), snapshot.isCurrent(at: date, calendar: calendar) else {
                return .needsRefresh
            }
            return snapshot.targetMillilitres == nil ? .needsGoal : .progress(snapshot)
        } catch {
            return .unavailable
        }
    }

    var title: String {
        switch self {
        case .progress: "Water today"
        case .needsGoal: "Set today's goal"
        case .needsRefresh: "Start today's routine"
        case .unavailable: "Progress unavailable"
        }
    }

    var guidance: String {
        switch self {
        case .progress: "Tap to record water."
        case .needsGoal: "Open the app to choose your daily target."
        case .needsRefresh: "Open the app to refresh today's water intake."
        case .unavailable: "Open the app to refresh your saved progress."
        }
    }
}
