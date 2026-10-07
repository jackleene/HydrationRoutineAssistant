import Foundation
import Testing
import UserNotifications
@testable import HydrationRoutineAssistant

struct HydrationNotificationResponseHandlerTests {
    @Test("Notification responses complete once on the main thread", arguments: [
        ("hydration.reminder.preview", UNNotificationDefaultActionIdentifier, ["openToday", "completion"]),
        ("hydration.reminder.123", HydrationNotificationIdentity.openTodayAction, ["openToday", "completion"]),
        ("hydration.reminder.preview", UNNotificationDismissActionIdentifier, ["completion"]),
        ("unrelated.notification", UNNotificationDefaultActionIdentifier, ["completion"]),
        ("hydration.reminder.preview", "UNKNOWN_ACTION", ["completion"])
    ])
    func responseCompletionUsesMainThread(
        requestIdentifier: String, actionIdentifier: String, expectedEvents: [String]
    ) async {
        let recorder = NotificationResponseRecorder()
        await Task.detached {
            await HydrationNotificationResponseHandler.handle(
                requestIdentifier: requestIdentifier,
                actionIdentifier: actionIdentifier,
                onOpenToday: { recorder.record("openToday") },
                completionHandler: { recorder.record("completion") }
            )
        }.value
        let events = recorder.events
        #expect(events.map(\.name) == expectedEvents)
        #expect(events.allSatisfy { $0.isMainThread })
    }
}

// The lock guards all mutable state because notification callbacks can run on different executors.
private final class NotificationResponseRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [(name: String, isMainThread: Bool)] = []

    func record(_ name: String) {
        lock.withLock { recordedEvents.append((name, Thread.isMainThread)) }
    }

    var events: [(name: String, isMainThread: Bool)] {
        lock.withLock { recordedEvents }
    }
}
