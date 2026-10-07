import Foundation

struct HydrationNotificationPresentation: Equatable, Sendable {
    let content: HydrationWidgetContent

    static func read(from store: any HydrationWidgetSnapshotStore, at date: Date, calendar: Calendar) -> Self {
        let content = HydrationWidgetContent.read(from: store, at: date, calendar: calendar)
        // A clock rollback must not present a snapshot saved in the future as current progress.
        if case .progress(let snapshot) = content, snapshot.updatedAt > date {
            return Self(content: .needsRefresh)
        }
        return Self(content: content)
    }

    var title: String {
        switch content {
        case .progress(let snapshot): snapshot.remainingMillilitres == 0 ? "Daily goal complete" : "Water-break check-in"
        default: content.title
        }
    }

    var guidance: String {
        switch content {
        case .progress(let snapshot):
            snapshot.remainingMillilitres == 0 ? "Open Today to review your water intake." :
                "Take a water break when it suits your routine. Open Today to record water after drinking."
        default: content.guidance
        }
    }
}
