import CoreData
import Foundation
import Testing
@testable import HydrationRoutineAssistant

struct HydrationSchemaTests {
    @Test("Saved water intake retains its daily goal")
    func savedIntakeRetainsDailyGoal() throws {
        let context = try makeContext()
        try context.performAndWait {
            let goal = insertGoalWithIntake(in: context)
            let goalID = try #require(goal.id)
            let day = try #require(goal.date)
            try context.save()
            context.reset()

            let entries = try context.fetch(WaterIntakeEntryEntity.fetchRequest())
            let entry = try #require(entries.first)
            let savedGoal = try #require(entry.goal)
            #expect(entries.count == 1)
            #expect(entry.amountMillilitres == 250)
            #expect(entry.recordedAt == day)
            #expect(savedGoal.id == goalID)
            #expect(savedGoal.date == day)
            #expect(savedGoal.targetMillilitres == 2_000)
            #expect(savedGoal.intakes?.contains(entry) == true)
        }
    }

    @Test("Deleting a daily goal removes its water intake records")
    func deletingGoalRemovesItsIntakes() throws {
        let context = try makeContext()
        try context.performAndWait {
            let goal = insertGoalWithIntake(in: context)
            try context.save()
            context.delete(goal)
            try context.save()
            context.reset()

            #expect(try context.count(for: HydrationGoalEntity.fetchRequest()) == 0)
            #expect(try context.count(for: WaterIntakeEntryEntity.fetchRequest()) == 0)
        }
    }

    private func makeContext() throws -> NSManagedObjectContext {
        let modelURL = try #require(Bundle.main.url(forResource: "HydrationModel", withExtension: "momd"))
        let model = try #require(NSManagedObjectModel(contentsOf: modelURL))
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        // Each test uses a separate store so it cannot change the app's saved intake history.
        try coordinator.addPersistentStore(
            ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil
        )
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }

    private func insertGoalWithIntake(in context: NSManagedObjectContext) -> HydrationGoalEntity {
        let day = Date(timeIntervalSince1970: 1_791_331_200)
        let goal = HydrationGoalEntity(context: context)
        goal.id = UUID()
        goal.date = day
        goal.targetMillilitres = 2_000

        let entry = WaterIntakeEntryEntity(context: context)
        entry.id = UUID()
        entry.amountMillilitres = 250
        entry.recordedAt = day
        entry.goal = goal
        return goal
    }
}
