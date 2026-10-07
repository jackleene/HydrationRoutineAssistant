import CoreData
import Foundation

@MainActor
final class UserDefaultsHydrationReminderRoutineStore: HydrationReminderRoutineStore {
    private let defaults: UserDefaults
    private let key = "hydration.reminderRoutine.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() throws -> HydrationReminderRoutine? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            let routine = try JSONDecoder().decode(HydrationReminderRoutine.self, from: data)
            try routine.validate()
            return routine
        } catch {
            throw HydrationRoutineStoreError.unreadablePreferences
        }
    }

    func save(_ routine: HydrationReminderRoutine) throws {
        do {
            let data = try JSONEncoder().encode(routine)
            defaults.set(data, forKey: key)
        } catch {
            throw HydrationRoutineStoreError.saveFailed
        }
    }
}

enum HydrationComposition {
    @MainActor
    static func makeWorkspace() async throws -> HydrationWorkspaceViewModel {
        let calendar = Calendar.current
        let container = try await HydrationPersistence.makeContainer()
        let repository = CoreDataHydrationRepository(container: container, calendar: calendar)
        return HydrationWorkspaceViewModel(
            repository: repository, routineStore: UserDefaultsHydrationReminderRoutineStore(), calendar: calendar
        )
    }
}

#if DEBUG
actor HydrationPreviewRepository: HydrationRepository {
    private var goals: [HydrationGoal] = []
    private var entries: [WaterIntakeEntry] = []

    func fetchGoal(on date: Date) async throws -> HydrationGoal? {
        goals.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func saveGoal(_ goal: HydrationGoal) async throws {
        goals.removeAll { $0.id == goal.id }
        goals.append(goal)
    }

    func fetchIntakes(for goalID: UUID, on date: Date) async throws -> [WaterIntakeEntry] {
        entries.filter { $0.goalID == goalID && Calendar.current.isDate($0.recordedAt, inSameDayAs: date) }
    }

    func saveIntake(_ entry: WaterIntakeEntry) async throws { entries.append(entry) }
}

@MainActor
final class HydrationPreviewRoutineStore: HydrationReminderRoutineStore {
    private var routine: HydrationReminderRoutine?
    func load() throws -> HydrationReminderRoutine? { routine }
    func save(_ routine: HydrationReminderRoutine) throws { self.routine = routine }
}
#endif
