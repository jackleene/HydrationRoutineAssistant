import Foundation
import Testing
@testable import HydrationRoutineAssistant

struct HydrationNotificationPresentationTests {
    private let date = Date(timeIntervalSince1970: 1_791_374_400)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func snapshot(target: Int? = 2_000, consumed: Int = 750, at date: Date? = nil) throws -> HydrationWidgetSnapshot {
        let date = date ?? self.date
        return try HydrationWidgetSnapshot(
            day: try #require(calendar.dateInterval(of: .day, for: date)),
            timeZoneIdentifier: calendar.timeZone.identifier, targetMillilitres: target,
            consumedMillilitres: consumed, lastIntakeAt: consumed > 0 ? date : nil, updatedAt: date
        )
    }

    @Test("Expanded reminders read current shared progress rather than a scheduling-time total")
    func currentProgressOffersWaterBreak() throws {
        let expected = try snapshot()
        let presentation = HydrationNotificationPresentation.read(from: NotificationSnapshotStub(snapshot: expected),
                                                                  at: date, calendar: calendar)
        #expect(presentation.content == .progress(expected))
        #expect(presentation.title == "Water-break check-in")
        #expect(presentation.guidance.contains("after drinking"))
    }

    @Test("Completed goals offer review rather than encouraging extra water", arguments: [2_000, 2_500])
    func reachedGoalsOfferReview(consumed: Int) throws {
        let expected = try snapshot(consumed: consumed)
        let presentation = HydrationNotificationPresentation.read(from: NotificationSnapshotStub(snapshot: expected),
                                                                  at: date, calendar: calendar)
        #expect(presentation.title == "Daily goal complete")
        #expect(presentation.guidance == "Open Today to review your water intake.")
        #expect(expected.remainingMillilitres == 0)
        #expect(expected.completionFraction == 1)
    }

    @Test("A reminder with no daily goal offers setup rather than an invented total")
    func missingGoalOffersSetup() throws {
        let presentation = HydrationNotificationPresentation.read(
            from: NotificationSnapshotStub(snapshot: try snapshot(target: nil, consumed: 0)), at: date, calendar: calendar
        )
        #expect(presentation.content == .needsGoal)
        #expect(presentation.title == "Set today's goal")
    }

    @Test("Old and future-dated progress never appears as today's notification total", arguments: [-86_400.0, 60.0])
    func staleAndFutureProgressOfferRefresh(offset: Double) throws {
        let presentation = HydrationNotificationPresentation.read(
            from: NotificationSnapshotStub(snapshot: try snapshot(at: date.addingTimeInterval(offset))),
            at: date, calendar: calendar
        )
        #expect(presentation.content == .needsRefresh)
        #expect(presentation.guidance.contains("refresh today's"))
    }

    @Test("A time-zone change requires fresh progress before expanding a reminder")
    func changedTimeZoneOffersRefresh() throws {
        var localCalendar = calendar
        localCalendar.timeZone = try #require(TimeZone(identifier: "Australia/Sydney"))
        let presentation = HydrationNotificationPresentation.read(
            from: NotificationSnapshotStub(snapshot: try snapshot()), at: date, calendar: localCalendar
        )
        #expect(presentation.content == .needsRefresh)
    }

    @Test("Unreadable shared storage gives a recoverable notification state")
    func unreadableSnapshotOffersRecovery() {
        let presentation = HydrationNotificationPresentation.read(
            from: AppGroupHydrationWidgetSnapshotStore(containerURL: nil), at: date, calendar: calendar
        )
        #expect(presentation.content == .unavailable)
        #expect(presentation.guidance == "Open the app to refresh your saved progress.")
    }

    @Test("An absent shared snapshot asks for refresh instead of inventing notification progress")
    func absentSnapshotOffersRefresh() {
        let presentation = HydrationNotificationPresentation.read(
            from: NotificationSnapshotStub(snapshot: nil), at: date, calendar: calendar
        )
        #expect(presentation.content == .needsRefresh)
        #expect(presentation.title == "Start today's routine")
        #expect(presentation.guidance == "Open the app to refresh today's water intake.")
    }

    @Test("The app embeds a custom notification extension for its water-break category")
    func embeddedExtensionMatchesReminderCategory() throws {
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        let bundle = try #require(Bundle(url: plugins.appendingPathComponent("HydrationNotificationContent.appex")))
        let configuration = try #require(bundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])
        let attributes = try #require(configuration["NSExtensionAttributes"] as? [String: Any])
        #expect(configuration["NSExtensionPointIdentifier"] as? String == "com.apple.usernotifications.content-extension")
        #expect(configuration["NSExtensionMainStoryboard"] as? String == "MainInterface")
        #expect(attributes["UNNotificationExtensionCategory"] as? String == HydrationNotificationIdentity.category)
        #expect(attributes["UNNotificationExtensionDefaultContentHidden"] as? Bool == true)
        #expect(attributes["UNNotificationExtensionUserInteractionEnabled"] as? Bool == true)
    }
}

private struct NotificationSnapshotStub: HydrationWidgetSnapshotStore {
    let snapshot: HydrationWidgetSnapshot?
    func load() throws -> HydrationWidgetSnapshot? { snapshot }
    func save(_ snapshot: HydrationWidgetSnapshot) throws { throw HydrationWidgetStoreError.unableToSaveSnapshot }
}
