import Foundation

enum HydrationSharedContainer {
    static let identifier = "group.com.mingchen.HydrationRoutineAssistant"
    static let snapshotFilename = "HydrationWidgetSnapshot.json"
}

protocol HydrationWidgetSnapshotStore: Sendable {
    func load() throws -> HydrationWidgetSnapshot?
    func save(_ snapshot: HydrationWidgetSnapshot) throws
}

struct AppGroupHydrationWidgetSnapshotStore: HydrationWidgetSnapshotStore {
    private let containerURL: URL?

    init(containerURL: URL? = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: HydrationSharedContainer.identifier
    )) {
        self.containerURL = containerURL
    }

    private var snapshotURL: URL {
        get throws {
            guard let containerURL else { throw HydrationWidgetStoreError.sharedContainerUnavailable }
            return containerURL.appendingPathComponent(HydrationSharedContainer.snapshotFilename)
        }
    }

    func load() throws -> HydrationWidgetSnapshot? {
        let url = try snapshotURL
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw HydrationWidgetStoreError.unreadableSnapshot
        }
        do {
            let snapshot = try JSONDecoder().decode(HydrationWidgetSnapshot.self, from: data)
            try snapshot.validate()
            return snapshot
        } catch {
            throw HydrationWidgetStoreError.unreadableSnapshot
        }
    }

    func save(_ snapshot: HydrationWidgetSnapshot) throws {
        let url = try snapshotURL
        do {
            try snapshot.validate()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            // Atomic replacement lets the extension read either complete snapshot, never a partial write.
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            throw HydrationWidgetStoreError.unableToSaveSnapshot
        }
    }
}

enum HydrationWidgetStoreError: LocalizedError, Equatable {
    case sharedContainerUnavailable
    case unreadableSnapshot
    case unableToSaveSnapshot

    var errorDescription: String? {
        switch self {
        case .sharedContainerUnavailable: "The widget's shared hydration storage is unavailable."
        case .unreadableSnapshot: "The widget's saved drinking progress could not be read."
        case .unableToSaveSnapshot: "Your drinking progress could not be shared with the widget."
        }
    }

    var recoverySuggestion: String? {
        "Your drinking records remain in the app. Reopen the app to refresh the widget's progress."
    }
}
