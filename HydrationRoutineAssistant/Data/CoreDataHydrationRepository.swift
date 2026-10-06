import CoreData
import Foundation

actor CoreDataHydrationRepository: HydrationRepository {
    private let context: NSManagedObjectContext
    private let calendar: Calendar

    init(container: NSPersistentContainer, calendar: Calendar = .current) {
        context = container.newBackgroundContext()
        context.mergePolicy = NSErrorMergePolicy
        self.calendar = calendar
    }

    func fetchGoal(on date: Date) async throws -> HydrationGoal? {
        let day = try dayInterval(containing: date)
        do {
            return try await context.perform { [context] in
                let request = HydrationGoalEntity.fetchRequest()
                request.predicate = NSPredicate(
                    format: "date >= %@ AND date < %@", day.start as NSDate, day.end as NSDate
                )
                request.fetchLimit = 2
                let goals = try context.fetch(request)
                guard goals.count <= 1 else { throw HydrationRepositoryError.invalidStoredData }
                return try goals.first.map(Self.domainGoal)
            }
        } catch let error as HydrationRepositoryError {
            throw error
        } catch {
            throw HydrationRepositoryError.readFailed
        }
    }

    func saveGoal(_ goal: HydrationGoal) async throws {
        let day = try dayInterval(containing: goal.date)
        do {
            try await context.perform { [context, calendar] in
                do {
                    let existing = try Self.goalEntity(id: goal.id, in: context)
                    if let existing {
                        guard let savedDate = existing.date else {
                            throw HydrationRepositoryError.invalidStoredData
                        }
                        guard calendar.isDate(savedDate, inSameDayAs: goal.date) else {
                            throw HydrationRepositoryError.goalDayMismatch
                        }
                    }

                    // The model cannot enforce goal ID uniqueness with its required intake relationship.
                    // Updating by ID and rejecting another goal for the day preserves both identities.
                    let request = HydrationGoalEntity.fetchRequest()
                    request.predicate = NSPredicate(
                        format: "date >= %@ AND date < %@", day.start as NSDate, day.end as NSDate
                    )
                    let dailyGoals = try context.fetch(request)
                    guard dailyGoals.allSatisfy({ $0.id == goal.id }) else {
                        throw HydrationRepositoryError.duplicateDailyGoal
                    }

                    let entity = try existing ?? Self.insertGoal(in: context)
                    entity.id = goal.id
                    entity.date = goal.date
                    entity.targetMillilitres = Int64(goal.targetMillilitres)
                    try context.save()
                } catch {
                    // Discard a failed write so a later successful save cannot persist partial changes.
                    context.rollback()
                    throw error
                }
            }
        } catch let error as HydrationRepositoryError {
            throw error
        } catch {
            throw HydrationRepositoryError.saveFailed
        }
    }

    func fetchIntakes(for goalID: UUID, on date: Date) async throws -> [WaterIntakeEntry] {
        let day = try dayInterval(containing: date)
        do {
            return try await context.perform { [context] in
                let request = WaterIntakeEntryEntity.fetchRequest()
                // Exclude the next midnight so adjacent days never count the same record.
                request.predicate = NSPredicate(
                    format: "goal.id == %@ AND recordedAt >= %@ AND recordedAt < %@",
                    goalID as NSUUID, day.start as NSDate, day.end as NSDate
                )
                request.sortDescriptors = [NSSortDescriptor(key: "recordedAt", ascending: true)]
                return try context.fetch(request).map(Self.domainIntake)
            }
        } catch let error as HydrationRepositoryError {
            throw error
        } catch {
            throw HydrationRepositoryError.readFailed
        }
    }

    func saveIntake(_ entry: WaterIntakeEntry) async throws {
        do {
            try await context.perform { [context, calendar] in
                do {
                    guard let goal = try Self.goalEntity(id: entry.goalID, in: context) else {
                        throw HydrationRepositoryError.missingGoal
                    }
                    guard let goalDate = goal.date else {
                        throw HydrationRepositoryError.invalidStoredData
                    }
                    guard calendar.isDate(goalDate, inSameDayAs: entry.recordedAt) else {
                        throw HydrationRepositoryError.goalDayMismatch
                    }

                    let request = WaterIntakeEntryEntity.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", entry.id as NSUUID)
                    request.fetchLimit = 2
                    let matches = try context.fetch(request)
                    guard matches.count <= 1 else { throw HydrationRepositoryError.invalidStoredData }
                    let entity = try matches.first ?? Self.insertIntake(in: context)
                    entity.id = entry.id
                    entity.amountMillilitres = Int64(entry.amountMillilitres)
                    entity.recordedAt = entry.recordedAt
                    entity.goal = goal
                    try context.save()
                } catch {
                    context.rollback()
                    throw error
                }
            }
        } catch let error as HydrationRepositoryError {
            throw error
        } catch {
            throw HydrationRepositoryError.saveFailed
        }
    }

    private func dayInterval(containing date: Date) throws -> DateInterval {
        guard let day = calendar.dateInterval(of: .day, for: date) else {
            throw HydrationRepositoryError.invalidDay
        }
        return day
    }

    private nonisolated static func goalEntity(
        id: UUID, in context: NSManagedObjectContext
    ) throws -> HydrationGoalEntity? {
        let request = HydrationGoalEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 2
        let matches = try context.fetch(request)
        guard matches.count <= 1 else { throw HydrationRepositoryError.invalidStoredData }
        return matches.first
    }

    private nonisolated static func insertGoal(in context: NSManagedObjectContext) throws -> HydrationGoalEntity {
        guard let entity = NSEntityDescription.entity(forEntityName: "HydrationGoalEntity", in: context) else {
            throw HydrationRepositoryError.storageUnavailable
        }
        return HydrationGoalEntity(entity: entity, insertInto: context)
    }

    private nonisolated static func insertIntake(in context: NSManagedObjectContext) throws -> WaterIntakeEntryEntity {
        guard let entity = NSEntityDescription.entity(forEntityName: "WaterIntakeEntryEntity", in: context) else {
            throw HydrationRepositoryError.storageUnavailable
        }
        return WaterIntakeEntryEntity(entity: entity, insertInto: context)
    }

    private nonisolated static func domainGoal(_ entity: HydrationGoalEntity) throws -> HydrationGoal {
        guard let id = entity.id, let date = entity.date,
              let target = Int(exactly: entity.targetMillilitres) else {
            throw HydrationRepositoryError.invalidStoredData
        }
        do {
            return try HydrationGoal(id: id, date: date, targetMillilitres: target)
        } catch {
            throw HydrationRepositoryError.invalidStoredData
        }
    }

    private nonisolated static func domainIntake(_ entity: WaterIntakeEntryEntity) throws -> WaterIntakeEntry {
        guard let id = entity.id, let goalID = entity.goal?.id, let recordedAt = entity.recordedAt,
              let amount = Int(exactly: entity.amountMillilitres) else {
            throw HydrationRepositoryError.invalidStoredData
        }
        do {
            // A device clock change must not make an already saved drinking time unreadable.
            return try WaterIntakeEntry(
                id: id, goalID: goalID, amountMillilitres: amount, recordedAt: recordedAt, now: recordedAt
            )
        } catch {
            throw HydrationRepositoryError.invalidStoredData
        }
    }
}
