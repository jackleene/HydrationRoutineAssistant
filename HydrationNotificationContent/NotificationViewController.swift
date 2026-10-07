import OSLog
import UIKit
import UserNotifications
import UserNotificationsUI

final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private let scrollView = UIScrollView()
    private let contentView = HydrationNotificationView()
    private let logger = Logger(
        subsystem: "com.mingchen.HydrationRoutineAssistant.HydrationNotificationContent",
        category: "notification-content"
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
        logger.info("Notification content view loaded.")
    }

    func didReceive(_ notification: UNNotification) {
        loadViewIfNeeded()
        contentView.update(with: .read(
            from: AppGroupHydrationWidgetSnapshotStore(), at: Date(), calendar: .current
        ))
        logger.info("Notification received; shared progress presentation updated.")
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        let measured = contentView.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        guard measured.height.isFinite, measured.height > 0 else { return }
        // Leave room for system actions; large Dynamic Type content remains vertically scrollable.
        let heightLimit = view.window?.windowScene.map { $0.screen.bounds.height * 0.65 } ?? 440
        let height = min(measured.height, heightLimit)
        if abs(preferredContentSize.height - height) > 1 || abs(preferredContentSize.width - width) > 1 {
            preferredContentSize = CGSize(width: width, height: height)
        }
    }

    func didReceive(
        _ response: UNNotificationResponse,
        completionHandler completion: @escaping (UNNotificationContentExtensionResponseOption) -> Void
    ) {
        let opensToday = response.actionIdentifier == HydrationNotificationIdentity.openTodayAction ||
            response.actionIdentifier == UNNotificationDefaultActionIdentifier
        completion(opensToday ? .dismissAndForwardAction : .dismiss)
    }
}
