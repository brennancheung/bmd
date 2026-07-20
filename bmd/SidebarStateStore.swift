import Foundation

final class SidebarStateStore {
    static let shared = SidebarStateStore()

    private let defaults: UserDefaults
    private let activityKey = "bmd.watchedActivity"
    private let projectFilesKey = "bmd.projectFiles"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadActivity() -> [WatchedActivityItem] {
        guard let data = defaults.data(forKey: activityKey),
              let items = try? JSONDecoder().decode([WatchedActivityItem].self, from: data) else {
            return []
        }
        return items.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func saveActivity(_ items: [WatchedActivityItem]) {
        save(items, key: activityKey)
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

    private func save<Value: Encodable>(_ value: Value, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
