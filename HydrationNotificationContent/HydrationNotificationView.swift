import UIKit

final class HydrationNotificationView: UIView {
    private let titleLabel = makeLabel(style: .headline)
    private let recordedLabel = makeLabel(style: .title2, bold: true)
    private let goalLabel = makeLabel(style: .body)
    private let remainingLabel = makeLabel(style: .body, bold: true)
    private let lastDrinkLabel = makeLabel(style: .callout)
    private let savedAtLabel = makeLabel(style: .callout)
    private let guidanceLabel = makeLabel(style: .body)
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let progressStack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayout()
    }

    func update(with presentation: HydrationNotificationPresentation) {
        titleLabel.text = presentation.title
        guidanceLabel.text = presentation.guidance
        guard case .progress(let snapshot) = presentation.content else {
            progressStack.isHidden = true
            return
        }
        progressStack.isHidden = false
        recordedLabel.text = "\(snapshot.consumedMillilitres.formatted()) mL recorded"
        goalLabel.text = "Daily goal: \((snapshot.targetMillilitres ?? 0).formatted()) mL"
        progressView.progress = Float(snapshot.completionFraction)
        progressView.accessibilityValue = snapshot.completionFraction.formatted(
            .percent.precision(.fractionLength(0))
        )
        remainingLabel.text = snapshot.remainingMillilitres == 0 ? "Your chosen goal is complete." :
            "\((snapshot.remainingMillilitres ?? 0).formatted()) mL remaining"
        lastDrinkLabel.text = snapshot.lastIntakeAt.map {
            "Last drink: \($0.formatted(date: .omitted, time: .shortened))"
        } ?? "No drinks recorded yet."
        savedAtLabel.text = "Saved at \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened)). Open Today for the latest progress."
    }

    private func configureLayout() {
        titleLabel.accessibilityTraits.insert(.header)
        progressView.progressTintColor = .label
        progressView.isAccessibilityElement = true
        progressView.accessibilityLabel = "Daily hydration goal progress"
        progressStack.axis = .vertical
        progressStack.spacing = 12
        for item in [recordedLabel, goalLabel, progressView, remainingLabel, lastDrinkLabel, savedAtLabel] {
            progressStack.addArrangedSubview(item)
        }
        progressStack.setCustomSpacing(4, after: recordedLabel)

        let stack = UIStackView(arrangedSubviews: [titleLabel, progressStack, guidanceLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
        update(with: HydrationNotificationPresentation(content: .needsRefresh))
    }

    private static func makeLabel(style: UIFont.TextStyle, bold: Bool = false) -> UILabel {
        let label = UILabel()
        let font = UIFont.preferredFont(forTextStyle: style)
        if bold, let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) {
            label.font = UIFont(descriptor: descriptor, size: 0)
        } else {
            label.font = font
        }
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textColor = .label
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }
}
