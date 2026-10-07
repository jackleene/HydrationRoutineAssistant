import SwiftUI
import WidgetKit

struct HydrationWidgetEntry: TimelineEntry {
    let date: Date
    let content: HydrationWidgetContent
}

struct HydrationWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HydrationWidgetEntry { sampleEntry() }

    func getSnapshot(in context: Context, completion: @escaping (HydrationWidgetEntry) -> Void) {
        completion(context.isPreview ? sampleEntry() : currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HydrationWidgetEntry>) -> Void) {
        let entry = currentEntry()
        let nextDay = Calendar.current.dateInterval(of: .day, for: entry.date)?.end
            ?? entry.date.addingTimeInterval(3_600)
        // The prebuilt midnight entry clears yesterday's total even if a fresh timeline is delayed.
        let midnight = HydrationWidgetEntry(date: nextDay, content: .needsRefresh)
        completion(Timeline(entries: [entry, midnight], policy: .after(nextDay)))
    }

    private func currentEntry() -> HydrationWidgetEntry {
        let date = Date()
        return HydrationWidgetEntry(
            date: date,
            content: .read(from: AppGroupHydrationWidgetSnapshotStore(), at: date, calendar: .current)
        )
    }

    private func sampleEntry() -> HydrationWidgetEntry {
        let date = Date()
        guard let day = Calendar.current.dateInterval(of: .day, for: date),
              let snapshot = try? HydrationWidgetSnapshot(
                day: day, timeZoneIdentifier: Calendar.current.timeZone.identifier, targetMillilitres: 2_000,
                consumedMillilitres: 750, lastIntakeAt: max(day.start, date.addingTimeInterval(-600)), updatedAt: date
              ) else { return HydrationWidgetEntry(date: date, content: .needsGoal) }
        return HydrationWidgetEntry(date: date, content: .progress(snapshot))
    }
}

struct HydrationWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HydrationWidgetEntry

    var body: some View {
        Group {
            switch entry.content {
            case .progress(let snapshot):
                if family == .systemMedium { HydrationMediumWidgetView(snapshot: snapshot) }
                else { HydrationSmallWidgetView(snapshot: snapshot) }
            default:
                HydrationWidgetEmptyView(content: entry.content)
            }
        }
        .widgetURL(HydrationWidgetIdentity.todayURL)
        .containerBackground(.background, for: .widget)
        .tint(Color("AccentColor"))
    }
}

private struct HydrationSmallWidgetView: View {
    let snapshot: HydrationWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Water today", systemImage: "drop.fill").font(.caption.bold())
                .foregroundStyle(Color("AccentColor"))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(snapshot.consumedMillilitres.formatted()) mL")
                    .font(.title2.bold()).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                Text("of \((snapshot.targetMillilitres ?? 0).formatted()) mL")
                    .font(.caption).foregroundStyle(.primary.opacity(0.72))
            }
            ProgressView(value: snapshot.completionFraction)
                .accessibilityLabel("Daily hydration goal progress")
                .accessibilityValue(snapshot.completionFraction.formatted(.percent.precision(.fractionLength(0))))
            Text(snapshot.remainingMillilitres == 0 ? "Goal complete" : "\((snapshot.remainingMillilitres ?? 0).formatted()) mL left")
                .font(.caption).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens today's water intake in the app")
    }
}

private struct HydrationMediumWidgetView: View {
    let snapshot: HydrationWidgetSnapshot

    var body: some View {
        HStack(spacing: 20) {
            Gauge(value: snapshot.completionFraction) {
                Text("Daily hydration goal progress")
            } currentValueLabel: {
                Text(snapshot.completionFraction, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.bold()).monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityValue(snapshot.completionFraction.formatted(.percent.precision(.fractionLength(0))))
            VStack(alignment: .leading, spacing: 6) {
                Label("Water today", systemImage: "drop.fill").font(.caption.bold())
                    .foregroundStyle(Color("AccentColor"))
                Text("\(snapshot.consumedMillilitres.formatted()) / \((snapshot.targetMillilitres ?? 0).formatted()) mL")
                    .font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(snapshot.remainingMillilitres == 0 ? "Daily goal complete" : "\((snapshot.remainingMillilitres ?? 0).formatted()) mL remaining")
                    .font(.subheadline).lineLimit(1).minimumScaleFactor(0.7)
                if let lastIntake = snapshot.lastIntakeAt {
                    HStack(spacing: 4) {
                        Text("Last drink")
                        Text(lastIntake, style: .time)
                    }
                    .font(.caption).foregroundStyle(.primary.opacity(0.72))
                } else {
                    Text("Tap to record your first drink.")
                        .font(.caption).foregroundStyle(.primary.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens today's water intake in the app")
    }
}

private struct HydrationWidgetEmptyView: View {
    let content: HydrationWidgetContent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "drop.fill").font(.title2).foregroundStyle(Color("AccentColor"))
                .accessibilityHidden(true)
            Text(content.title).font(.headline)
            Text(content.guidance).font(.caption).foregroundStyle(.primary.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct HydrationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HydrationWidgetIdentity.kind, provider: HydrationWidgetProvider()) { entry in
            HydrationWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Daily water intake")
        .description("See today's drinking progress between work breaks. Tap to record water in the app.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    HydrationWidget()
} timeline: {
    HydrationWidgetEntry(date: .now, content: .needsGoal)
}

#Preview(as: .systemMedium) {
    HydrationWidget()
} timeline: {
    HydrationWidgetEntry(date: .now, content: .needsRefresh)
}
