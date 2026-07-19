import Foundation

struct BookmarkItem: Identifiable, Codable, Hashable {
    var id: String { path }
    /// Absolute path string (v1; security-scoped bookmarks in phase 2).
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

/// Persistence for recents and pinned folders (UserDefaults path lists for v1).
final class RecentStore {
    static let shared = RecentStore()

    private let defaults: UserDefaults
    private let recentsKey = "bmd.recents"
    private let pinsKey = "bmd.pins"
    private let maxRecents = 40

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadRecents() -> [BookmarkItem] {
        decode(key: recentsKey)
    }

    func loadPins() -> [BookmarkItem] {
        decode(key: pinsKey)
    }

    @discardableResult
    func rememberRecent(_ url: URL, at date: Date = Date()) -> [BookmarkItem] {
        var items = loadRecents()
        let path = url.standardizedFileURL.path
        items.removeAll { $0.path == path }
        items.insert(BookmarkItem.file(url, at: date), at: 0)
        if items.count > maxRecents {
            items = Array(items.prefix(maxRecents))
        }
        save(items, key: recentsKey)
        return items
    }

    @discardableResult
    func removeRecent(_ item: BookmarkItem) -> [BookmarkItem] {
        var items = loadRecents()
        items.removeAll { $0.id == item.id }
        save(items, key: recentsKey)
        return items
    }

    @discardableResult
    func clearRecents() -> [BookmarkItem] {
        save([], key: recentsKey)
        return []
    }

    @discardableResult
    func pinFolder(_ url: URL) -> [BookmarkItem] {
        var items = loadPins()
        let path = url.standardizedFileURL.path
        guard !items.contains(where: { $0.path == path }) else { return items }
        items.insert(BookmarkItem.folder(url), at: 0)
        save(items, key: pinsKey)
        return items
    }

    @discardableResult
    func unpin(_ item: BookmarkItem) -> [BookmarkItem] {
        var items = loadPins()
        items.removeAll { $0.id == item.id }
        save(items, key: pinsKey)
        return items
    }

    func resolve(_ item: BookmarkItem) -> URL? {
        let url = item.url
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func listMarkdownFiles(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var results: [URL] = []
        let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

        for case let fileURL as URL in enumerator {
            // Stay shallow-ish: depth 3 under pin for snappy sidebar.
            let relative = fileURL.path.replacingOccurrences(of: folder.path, with: "")
            let depth = relative.split(separator: "/").count
            if depth > 3 {
                enumerator.skipDescendants()
                continue
            }
            if markdownExtensions.contains(fileURL.pathExtension.lowercased()) {
                results.append(fileURL)
            }
        }

        return results.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private func decode(key: String) -> [BookmarkItem] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([BookmarkItem].self, from: data)) ?? []
    }

    private func save(_ items: [BookmarkItem], key: String) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}
