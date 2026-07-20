import Foundation

struct OpenDocumentItem: Identifiable, Codable, Hashable {
    let path: String
    var displayName: String
    let addedAt: Date
    var lastViewedAt: Date
    var isPinned: Bool

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }

    init(
        path: String,
        displayName: String,
        addedAt: Date,
        lastViewedAt: Date,
        isPinned: Bool = false
    ) {
        self.path = path
        self.displayName = displayName
        self.addedAt = addedAt
        self.lastViewedAt = lastViewedAt
        self.isPinned = isPinned
    }

    init(file: URL, at date: Date) {
        let normalized = file.standardizedFileURL
        self.init(
            path: normalized.path,
            displayName: normalized.lastPathComponent,
            addedAt: date,
            lastViewedAt: date
        )
    }

    init(legacy item: BookmarkItem) {
        self.init(
            path: item.path,
            displayName: item.displayName,
            addedAt: item.lastOpenedAt,
            lastViewedAt: item.lastOpenedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case displayName
        case addedAt
        case lastViewedAt
        case isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        displayName = try container.decode(String.self, forKey: .displayName)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        lastViewedAt = try container.decode(Date.self, forKey: .lastViewedAt)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}

struct DocumentHistoryState: Codable, Equatable {
    private(set) var entries: [String]
    private(set) var currentIndex: Int?

    init(entries: [String] = [], currentIndex: Int? = nil) {
        self.entries = entries
        if let currentIndex, entries.indices.contains(currentIndex) {
            self.currentIndex = currentIndex
        } else {
            self.currentIndex = entries.isEmpty ? nil : entries.count - 1
        }
    }

    var canGoBack: Bool {
        guard let currentIndex else { return false }
        return currentIndex > 0
    }

    var canGoForward: Bool {
        guard let currentIndex else { return false }
        return currentIndex < entries.count - 1
    }

    var pathsMostRecentFirst: [String] {
        var seen = Set<String>()
        return entries.reversed().filter { seen.insert($0).inserted }
    }

    mutating func record(_ path: String, maximumCount: Int = 100) {
        guard entries[safe: currentIndex] != path else { return }

        if let currentIndex, currentIndex < entries.count - 1 {
            entries.removeSubrange((currentIndex + 1)...)
        }
        entries.append(path)
        if entries.count > maximumCount {
            entries.removeFirst(entries.count - maximumCount)
        }
        currentIndex = entries.count - 1
    }

    mutating func goBack() -> String? {
        guard canGoBack, let currentIndex else { return nil }
        self.currentIndex = currentIndex - 1
        return entries[currentIndex - 1]
    }

    mutating func goForward() -> String? {
        guard canGoForward, let currentIndex else { return nil }
        self.currentIndex = currentIndex + 1
        return entries[currentIndex + 1]
    }
}

enum OpenDocumentTraversalDirection: Equatable {
    case previous
    case next
}

enum DocumentCandidateSource: String, Codable, Hashable {
    case open
    case update
    case project
    case history

    var title: String {
        switch self {
        case .open: "Open"
        case .update: "Update"
        case .project: "Project"
        case .history: "History"
        }
    }

    var systemImage: String {
        switch self {
        case .open: "doc.text"
        case .update: "sparkles"
        case .project: "folder"
        case .history: "clock.arrow.circlepath"
        }
    }
}

struct DocumentCandidate: Identifiable, Hashable {
    let path: String
    let displayName: String
    let contextLabel: String
    let source: DocumentCandidateSource
    let activityDate: Date
    let hasUnreadUpdate: Bool

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
}

enum DocumentNavigation {
    static func rememberOpen(
        _ file: URL,
        in existing: [OpenDocumentItem],
        at date: Date
    ) -> [OpenDocumentItem] {
        let normalized = file.standardizedFileURL
        var result = existing
        if let index = result.firstIndex(where: { $0.path == normalized.path }) {
            result[index].displayName = normalized.lastPathComponent
            result[index].lastViewedAt = date
            return result
        }

        result.append(OpenDocumentItem(file: normalized, at: date))
        return result
    }

    static func document(
        atShortcutPosition position: Int,
        in existing: [OpenDocumentItem]
    ) -> OpenDocumentItem? {
        guard (1...9).contains(position) else { return nil }
        return existing[safe: position - 1]
    }

    static func adjacentDocument(
        to currentPath: String?,
        direction: OpenDocumentTraversalDirection,
        in existing: [OpenDocumentItem]
    ) -> OpenDocumentItem? {
        guard !existing.isEmpty else { return nil }
        guard let currentPath,
              let currentIndex = existing.firstIndex(where: { $0.path == currentPath }) else {
            return direction == .next ? existing.first : existing.last
        }

        let offset = direction == .next ? 1 : -1
        let destinationIndex = (currentIndex + offset + existing.count) % existing.count
        return existing[destinationIndex]
    }

    static func replacementAfterClosing(
        path: String,
        in existing: [OpenDocumentItem]
    ) -> OpenDocumentItem? {
        guard let removedIndex = existing.firstIndex(where: { $0.path == path }) else {
            return nil
        }
        let remaining = existing.filter { $0.path != path }
        guard !remaining.isEmpty else { return nil }
        return remaining[min(removedIndex, remaining.count - 1)]
    }

    static func togglePin(
        path: String,
        in existing: [OpenDocumentItem]
    ) -> [OpenDocumentItem] {
        var result = existing
        guard let index = result.firstIndex(where: { $0.path == path }) else {
            return result
        }
        result[index].isPinned.toggle()
        return result
    }

    static func move(
        path: String,
        by offset: Int,
        in existing: [OpenDocumentItem]
    ) -> [OpenDocumentItem] {
        guard let sourceIndex = existing.firstIndex(where: { $0.path == path }) else {
            return existing
        }
        let destinationIndex = min(max(sourceIndex + offset, 0), existing.count - 1)
        guard destinationIndex != sourceIndex else { return existing }
        var result = existing
        let item = result.remove(at: sourceIndex)
        result.insert(item, at: destinationIndex)
        return result
    }

    static func candidates(
        openDocuments: [OpenDocumentItem],
        updates: [WatchedActivityItem],
        projects: [BookmarkItem],
        projectFilesByFolder: [String: [BookmarkItem]],
        history: DocumentHistoryState,
        currentPath: String?,
        query: String
    ) -> [DocumentCandidate] {
        let unreadByPath = Dictionary(
            updates.filter { $0.readAt == nil }.map { ($0.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var byPath: [String: DocumentCandidate] = [:]

        for item in openDocuments {
            byPath[item.path] = DocumentCandidate(
                path: item.path,
                displayName: item.displayName,
                contextLabel: contextLabel(for: item.url, projects: projects),
                source: .open,
                activityDate: item.lastViewedAt,
                hasUnreadUpdate: unreadByPath[item.path] != nil
            )
        }

        for item in updates where item.readAt == nil && byPath[item.path] == nil {
            byPath[item.path] = DocumentCandidate(
                path: item.path,
                displayName: item.displayName,
                contextLabel: item.contextLabel,
                source: .update,
                activityDate: item.detectedAt,
                hasUnreadUpdate: true
            )
        }

        for project in projects {
            for item in projectFilesByFolder[project.path] ?? [] where byPath[item.path] == nil {
                byPath[item.path] = DocumentCandidate(
                    path: item.path,
                    displayName: item.displayName,
                    contextLabel: contextLabel(for: item.url, projects: projects),
                    source: .project,
                    activityDate: item.lastOpenedAt,
                    hasUnreadUpdate: unreadByPath[item.path] != nil
                )
            }
        }

        for path in history.pathsMostRecentFirst where byPath[path] == nil {
            let url = URL(fileURLWithPath: path)
            byPath[path] = DocumentCandidate(
                path: path,
                displayName: url.lastPathComponent,
                contextLabel: contextLabel(for: url, projects: projects),
                source: .history,
                activityDate: .distantPast,
                hasUnreadUpdate: unreadByPath[path] != nil
            )
        }

        let terms = query
            .lowercased()
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
        return byPath.values
            .filter { candidate in
                guard !terms.isEmpty else { return true }
                let searchable = "\(candidate.displayName) \(candidate.contextLabel) \(candidate.path)"
                    .lowercased()
                return terms.allSatisfy(searchable.contains)
            }
            .sorted { left, right in
                let leftScore = rankingScore(left, currentPath: currentPath, terms: terms)
                let rightScore = rankingScore(right, currentPath: currentPath, terms: terms)
                if leftScore != rightScore { return leftScore > rightScore }
                if left.activityDate != right.activityDate {
                    return left.activityDate > right.activityDate
                }
                return left.displayName.localizedCaseInsensitiveCompare(right.displayName)
                    == .orderedAscending
            }
    }

    private static func contextLabel(for file: URL, projects: [BookmarkItem]) -> String {
        guard let project = SidebarFileState.containingProject(
            for: file,
            projects: projects
        ) else {
            return file.deletingLastPathComponent().lastPathComponent
        }
        let relative = MarkdownFolderDiscovery.relativePath(for: file, in: project.url)
        let directory = (relative as NSString).deletingLastPathComponent
        return directory.isEmpty ? project.displayName : "\(project.displayName) / \(directory)"
    }

    private static func rankingScore(
        _ candidate: DocumentCandidate,
        currentPath: String?,
        terms: [String]
    ) -> Int {
        var score: Int
        switch candidate.source {
        case .open: score = 400
        case .update: score = 300
        case .project: score = 200
        case .history: score = 100
        }
        if candidate.hasUnreadUpdate { score += 25 }
        if candidate.path == currentPath { score -= 450 }
        let name = candidate.displayName.lowercased()
        for term in terms {
            if name == term { score += 200 }
            else if name.hasPrefix(term) { score += 100 }
            else if name.contains(term) { score += 50 }
        }
        return score
    }
}

private extension Collection {
    subscript(safe index: Index?) -> Element? {
        guard let index, indices.contains(index) else { return nil }
        return self[index]
    }
}
