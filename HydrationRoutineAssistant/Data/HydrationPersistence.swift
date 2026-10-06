import CoreData
import Foundation

enum HydrationPersistence {
    static func makeContainer(storeURL: URL? = nil) async throws -> NSPersistentContainer {
        let bundle = Bundle(for: HydrationGoalEntity.self)
        guard let modelURL = bundle.url(forResource: "HydrationModel", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            throw HydrationRepositoryError.storageUnavailable
        }

        let databaseURL = storeURL ?? NSPersistentContainer.defaultDirectoryURL()
            .appendingPathComponent("HydrationModel.sqlite")
        do {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
        } catch {
            throw HydrationRepositoryError.storageUnavailable
        }

        let container = NSPersistentContainer(name: "HydrationModel", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: databaseURL)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = true
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if error != nil {
                    continuation.resume(throwing: HydrationRepositoryError.storageUnavailable)
                } else {
                    continuation.resume()
                }
            }
        }
        return container
    }
}
