import Foundation

struct HydrationProgress: Equatable, Sendable {
    let goal: HydrationGoal
    let consumedMillilitres: Int

    /// Calendar days follow the supplied time zone and calendar; a fixed 24-hour
    /// window would not reliably represent the goal's day.
    init(goal: HydrationGoal, entries: [WaterIntakeEntry], calendar: Calendar) {
        self.goal = goal
        self.consumedMillilitres = entries.reduce(0) { total, entry in
            guard entry.goalID == goal.id,
                  calendar.isDate(entry.recordedAt, inSameDayAs: goal.date) else {
                return total
            }
            return total + entry.amountMillilitres
        }
    }

    var remainingMillilitres: Int {
        max(goal.targetMillilitres - consumedMillilitres, 0)
    }

    // Cap the display fraction while preserving intake totals above the target.
    var completionFraction: Double {
        min(Double(consumedMillilitres) / Double(goal.targetMillilitres), 1)
    }

    var isGoalReached: Bool {
        consumedMillilitres >= goal.targetMillilitres
    }
}
