import Foundation

final class SidebarStateStore {
    static let shared = SidebarStateStore()

    private let defaults: UserDefaults
    private let activityKey = "bmd.watchedActivity"
    private let projectFilesKey = "bmd.projectFiles"
    private let historyKey = "bmd.documentHistory"
    private let activityVersionKey = "bmd.watchedActivityVersion"
    private let currentActivityVersion = 2

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadActivity() -> [WatchedActivityItem] {
        guard let data = defaults.data(forKey: activityKey) else {
            defaults.set(currentActivityVersion, forKey: activityVersionKey)
            return []
        }
        guard let items = try? JSONDecoder().decode(
            [WatchedActivityItem].self,
            from: data
        ) else {
            defaults.set(currentActivityVersion, forKey: activityVersionKey)
            return []
        }
        let existing = items.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard defaults.integer(forKey: activityVersionKey) < currentActivityVersion else {
            return existing
        }
        let migrated = existing.map { item in
            var read = item
            read.readAt = item.detectedAt
            return read
        }
        saveActivity(migrated)
        defaults.set(currentActivityVersion, forKey: activityVersionKey)
        return migrated
    }

    func saveActivity(_ items: [WatchedActivityItem]) {
        save(items, key: activityKey)
        defaults.set(currentActivityVersion, forKey: activityVersionKey)
    }

    func loadProjectFiles() -> [String: [BookmarkItem]] {
        guard let data = defaults.data(forKey: projectFilesKey),
              let items = try? JSONDecoder().decode(
                [String: [BookmarkItem]].self,
                from: data
              ) else {
            return [:]
        }
        return items.mapValues { files in
            files.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    func saveProjectFiles(_ items: [String: [BookmarkItem]]) {
        save(items, key: projectFilesKey)
    }

    func loadHistory() -> DocumentHistoryState {
        guard let data = defaults.data(forKey: historyKey),
              let history = try? JSONDecoder().decode(
                DocumentHistoryState.self,
                from: data
              ) else {
            return DocumentHistoryState()
        }
        let existingPaths = history.entries.filter {
            FileManager.default.fileExists(atPath: $0)
        }
        return DocumentHistoryState(entries: existingPaths)
    }

    func saveHistory(_ history: DocumentHistoryState) {
        save(history, key: historyKey)
    }

    private func save<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
