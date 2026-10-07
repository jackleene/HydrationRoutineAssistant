import SwiftUI

enum HydrationTheme {
    static let accent = Color("AccentColor")
    static let supportingText = Color.primary.opacity(0.72)
    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let buttonTint = Color(red: 0.03, green: 0.42, blue: 0.8)
}

struct HydrationCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(HydrationTheme.surface, in: .rect(cornerRadius: 20))
    }
}

struct HydrationIssueView: View {
    let issue: HydrationIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.red).accessibilityHidden(true)
                Text(issue.message)
            }
            if let recovery = issue.recovery {
                Text(recovery).foregroundStyle(HydrationTheme.supportingText)
            }
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

struct HydrationConfirmationView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.callout)
            .foregroundStyle(.primary)
            .accessibilityElement(children: .combine)
    }
}

struct HydrationMetricView: View {
    let title: String
    let millilitres: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(HydrationTheme.supportingText)
            Text("\(millilitres.formatted()) mL").font(.title2.bold()).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

struct HydrationProgressCard: View {
    let progress: HydrationProgress
    @ScaledMetric(relativeTo: .title) private var ringSize: CGFloat = 152

    var body: some View {
        HydrationCard {
            VStack(alignment: .leading, spacing: 20) {
                Label("Daily water intake", systemImage: "drop.fill").font(.headline)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) {
                        HydrationProgressRing(progress: progress, size: min(ringSize, 200))
                        HydrationProgressMetrics(progress: progress)
                    }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 24) {
                        HydrationProgressRing(progress: progress, size: min(ringSize, 200))
                            .frame(maxWidth: .infinity)
                        HydrationProgressMetrics(progress: progress)
                    }
                }
                Text(progress.isGoalReached ? "Your daily goal is complete." : "\(progress.remainingMillilitres.formatted()) mL remaining to reach your chosen goal.")
                    .font(.callout)
                    .foregroundStyle(HydrationTheme.supportingText)
            }
        }
    }
}

private struct HydrationProgressMetrics: View {
    let progress: HydrationProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HydrationMetricView(title: "Recorded", millilitres: progress.consumedMillilitres)
            HydrationMetricView(title: "Daily goal", millilitres: progress.goal.targetMillilitres)
        }
    }
}

private struct HydrationProgressRing: View {
    let progress: HydrationProgress
    let size: CGFloat

    var body: some View {
        Circle()
            .stroke(.quaternary, lineWidth: 12)
            .overlay {
                Circle().trim(from: 0, to: CGFloat(progress.completionFraction))
                    .stroke(HydrationTheme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: progress.isGoalReached ? "checkmark" : "drop.fill")
                        .foregroundStyle(HydrationTheme.accent)
                        .accessibilityHidden(true)
                    Text(progress.completionFraction, format: .percent.precision(.fractionLength(0)))
                        .font(.title.bold()).minimumScaleFactor(0.7)
                }
            }
            .frame(width: size, height: size)
            .padding(8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Daily goal progress")
            .accessibilityValue(progress.completionFraction.formatted(.percent.precision(.fractionLength(0))))
    }
}

struct HydrationIntakeRow: View {
    let entry: WaterIntakeEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "drop.fill").foregroundStyle(HydrationTheme.accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(entry.amountMillilitres.formatted()) mL").font(.headline)
                Text(entry.recordedAt, format: .dateTime.hour().minute()).font(.subheadline)
                    .foregroundStyle(HydrationTheme.supportingText)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
