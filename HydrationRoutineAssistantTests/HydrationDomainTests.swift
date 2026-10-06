import Foundation
import Testing
@testable import HydrationRoutineAssistant

struct HydrationDomainTests {
    private let now = Date(timeIntervalSince1970: 1_791_331_200)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        // Fix the time zone so day-boundary tests do not depend on the host settings.
        calendar.timeZone = TimeZone(secondsFromGMT: 10 * 60 * 60)!
        return calendar
    }

    @Test("Daily goals accept both supported boundaries", arguments: [500, 2_000, 5_000])
    func dailyGoalAcceptsSupportedTarget(_ target: Int) throws {
        let id = UUID()
        let goal = try HydrationGoal(id: id, date: now, targetMillilitres: target)
        #expect(goal.id == id)
        #expect(goal.targetMillilitres == target)
    }

    @Test("Daily goals reject unsupported targets", arguments: [-1, 0, 499, 5_001])
    func dailyGoalRejectsUnsupportedTarget(_ target: Int) {
        #expect(throws: HydrationGoal.ValidationError.targetOutsideSupportedRange) {
            try HydrationGoal(date: now, targetMillilitres: target)
        }
    }

    @Test("Water intake accepts supported amounts", arguments: [1, 250, 1_000])
    func waterIntakeAcceptsSupportedAmount(_ amount: Int) throws {
        let goalID = UUID()
        let entry = try WaterIntakeEntry(
            goalID: goalID, amountMillilitres: amount, recordedAt: now, now: now
        )
        #expect(entry.goalID == goalID)
        #expect(entry.amountMillilitres == amount)
    }

    @Test("Water intake rejects unsupported amounts", arguments: [-1, 0, 1_001])
    func waterIntakeRejectsUnsupportedAmount(_ amount: Int) {
        #expect(throws: WaterIntakeEntry.ValidationError.amountOutsideSupportedRange) {
            try WaterIntakeEntry(
                goalID: UUID(), amountMillilitres: amount, recordedAt: now, now: now
            )
        }
    }

    @Test("Water intake rejects a future drinking time")
    func waterIntakeRejectsFutureTime() {
        #expect(throws: WaterIntakeEntry.ValidationError.recordedInFuture) {
            try WaterIntakeEntry(
                goalID: UUID(), amountMillilitres: 250,
                recordedAt: now.addingTimeInterval(1), now: now
            )
        }
    }

    @Test("Daily progress starts empty")
    func emptyDayHasNoRecordedWater() throws {
        let goal = try HydrationGoal(date: now, targetMillilitres: 2_000)
        let progress = HydrationProgress(goal: goal, entries: [], calendar: calendar)
        #expect(progress.consumedMillilitres == 0)
        #expect(progress.remainingMillilitres == 2_000)
        #expect(progress.completionFraction == 0)
        #expect(!progress.isGoalReached)
    }

    @Test("Daily progress combines the goal's drinking-water records")
    func dailyProgressCombinesIntakes() throws {
        let goal = try HydrationGoal(date: now, targetMillilitres: 2_000)
        let entries = try [250, 750].map {
            try WaterIntakeEntry(
                goalID: goal.id, amountMillilitres: $0, recordedAt: now, now: now
            )
        }
        let progress = HydrationProgress(goal: goal, entries: entries, calendar: calendar)
        #expect(progress.consumedMillilitres == 1_000)
        #expect(progress.remainingMillilitres == 1_000)
        #expect(progress.completionFraction == 0.5)
        #expect(!progress.isGoalReached)
    }

    @Test("Daily progress excludes other goals and adjacent days")
    func dailyProgressUsesGoalAndCalendarDay() throws {
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = try #require(calendar.date(byAdding: .day, value: 1, to: dayStart))
        let goal = try HydrationGoal(date: now, targetMillilitres: 2_000)
        let clock = dayEnd.addingTimeInterval(1)
        let entries = try [
            WaterIntakeEntry(goalID: goal.id, amountMillilitres: 100, recordedAt: dayStart, now: clock),
            WaterIntakeEntry(goalID: goal.id, amountMillilitres: 200, recordedAt: dayEnd.addingTimeInterval(-1), now: clock),
            WaterIntakeEntry(goalID: goal.id, amountMillilitres: 400, recordedAt: dayStart.addingTimeInterval(-1), now: clock),
            WaterIntakeEntry(goalID: goal.id, amountMillilitres: 800, recordedAt: dayEnd, now: clock),
            WaterIntakeEntry(goalID: UUID(), amountMillilitres: 500, recordedAt: now, now: clock)
        ]
        let progress = HydrationProgress(goal: goal, entries: entries, calendar: calendar)
        #expect(progress.consumedMillilitres == 300)
    }

    @Test("Reaching or exceeding a goal caps the progress indicator", arguments: [500, 750])
    func completedGoalHasNoRemainingWater(_ amount: Int) throws {
        let goal = try HydrationGoal(date: now, targetMillilitres: 500)
        let entry = try WaterIntakeEntry(
            goalID: goal.id, amountMillilitres: amount, recordedAt: now, now: now
        )
        let progress = HydrationProgress(goal: goal, entries: [entry], calendar: calendar)
        #expect(progress.consumedMillilitres == amount)
        #expect(progress.remainingMillilitres == 0)
        #expect(progress.completionFraction == 1)
        #expect(progress.isGoalReached)
    }

    @Test("Hydration validation errors explain recovery")
    func hydrationErrorsOfferRecovery() throws {
        let goalError = HydrationGoal.ValidationError.targetOutsideSupportedRange
        let amountError = WaterIntakeEntry.ValidationError.amountOutsideSupportedRange
        let timeError = WaterIntakeEntry.ValidationError.recordedInFuture
        #expect(!(try #require(goalError.recoverySuggestion)).isEmpty)
        #expect(!(try #require(amountError.recoverySuggestion)).isEmpty)
        #expect(!(try #require(timeError.recoverySuggestion)).isEmpty)
    }
}
