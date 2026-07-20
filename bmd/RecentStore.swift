import Foundation

struct BookmarkItem: Identifiable, Codable, Hashable {
    var id: String { path }
    /// Absolute path string (v1; directory bookmarks only if sandboxing is added later).
    var path: String
    var displayName: String
    var isDirectory: Bool
    var lastOpenedAt: Date

    var url: URL {
        URL(fileURLWithPath: path)
    }

    static func file(_ url: URL, at date: Date = Date()) -> BookmarkItem {
        BookmarkItem(
            path: url.standardizedFileURL.path,
            displayName: url.lastPathComponent,
            isDirectory: false,
            lastOpenedAt: date
        )
    }

    static func folder(_ url: URL, at date: Date = Date()) -> BookmarkItem {
        BookmarkItem(
            path: url.standardizedFileURL.path,
            displayName: url.lastPathComponent,
            isDirectory: true,
            lastOpenedAt: date
        )
    }
}

/// Persistence for open documents, legacy recents migration, and project folders.
final class RecentStore {
    static let shared = RecentStore()

    private let defaults: UserDefaults
    private let recentsKey = "bmd.recents"
    private let openDocumentsKey = "bmd.openDocuments"
    // Keep the original key so existing pinned folders migrate into Projects.
    private let projectsKey = "bmd.pins"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadRecents() -> [BookmarkItem] {
        decode(key: recentsKey)
    }

    func loadProjects() -> [BookmarkItem] {
        decode(key: projectsKey)
    }

    func loadOpenDocuments() -> [OpenDocumentItem] {
        if let items: [OpenDocumentItem] = decodeIfPresent(key: openDocumentsKey) {
            return items.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        let migrated = loadRecents().map(OpenDocumentItem.init(legacy:))
        saveOpenDocuments(migrated)
        return migrated
    }

    func saveOpenDocuments(_ items: [OpenDocumentItem]) {
        save(items, key: openDocumentsKey)
    }

    @discardableResult
    func addProject(_ url: URL) -> [BookmarkItem] {
        var items = loadProjects()
        let path = url.standardizedFileURL.path
        guard !items.contains(where: { $0.path == path }) else { return items }
        items.insert(BookmarkItem.folder(url), at: 0)
        save(items, key: projectsKey)
        return items
    }

    @discardableResult
    func removeProject(_ item: BookmarkItem) -> [BookmarkItem] {
        var items = loadProjects()
        items.removeAll { $0.id == item.id }
        save(items, key: projectsKey)
        return items
    }

    func resolve(_ item: BookmarkItem) -> URL? {
        let url = item.url
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func decode(key: String) -> [BookmarkItem] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([BookmarkItem].self, from: data)) ?? []
    }

    private func decodeIfPresent<Value: Decodable>(key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private func save<Value: Encodable>(_ items: Value, key: String) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}
