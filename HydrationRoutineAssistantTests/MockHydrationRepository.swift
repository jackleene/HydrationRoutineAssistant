import Foundation
@testable import HydrationRoutineAssistant

actor MockHydrationRepository: HydrationRepository {
    private var goal: HydrationGoal?
    private var entries: [WaterIntakeEntry]
    private let failingOperation: Operation?
    private let injectedFailure: any Error
    private(set) var requestedGoalDates: [Date] = []
    private(set) var intakeQueries: [IntakeQuery] = []
    private(set) var savedGoals: [HydrationGoal] = []
    private(set) var savedIntakes: [WaterIntakeEntry] = []

    init(
        goal: HydrationGoal? = nil,
        entries: [WaterIntakeEntry] = [],
        failingOperation: Operation? = nil,
        injectedFailure: any Error = SimulatedFailure.unavailable
    ) {
        self.goal = goal
        self.entries = entries
        self.failingOperation = failingOperation
        self.injectedFailure = injectedFailure
    }

    func fetchGoal(on date: Date) async throws -> HydrationGoal? {
        requestedGoalDates.append(date)
        if failingOperation == .fetchGoal { throw injectedFailure }
        return goal
    }

    func saveGoal(_ goal: HydrationGoal) async throws {
        if failingOperation == .saveGoal { throw injectedFailure }
        savedGoals.append(goal)
        self.goal = goal
    }

    func fetchIntakes(for goalID: UUID, on date: Date) async throws -> [WaterIntakeEntry] {
        intakeQueries.append(IntakeQuery(goalID: goalID, date: date))
        if failingOperation == .fetchIntakes { throw injectedFailure }
        return entries
    }

    func saveIntake(_ entry: WaterIntakeEntry) async throws {
        if failingOperation == .saveIntake { throw injectedFailure }
        savedIntakes.append(entry)
        entries.append(entry)
    }

    struct IntakeQuery: Equatable, Sendable {
        let goalID: UUID
        let date: Date
    }

    enum Operation: Sendable {
        case fetchGoal
        case saveGoal
        case fetchIntakes
        case saveIntake
    }

    enum SimulatedFailure: Error {
        case unavailable
    }
}
