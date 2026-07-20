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

enum DocumentSearchScope: Equatable {
    case global
    case project(BookmarkItem)
    case unavailableProject(URL?)

    var title: String {
        switch self {
        case .global:
            "All Projects"
        case let .project(project):
            project.displayName
        case .unavailableProject:
            "Current Project"
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
    let displayNameMatchRanges: [FuzzyMatchRange]
    let contextMatchRanges: [FuzzyMatchRange]

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }

    init(
        path: String,
        displayName: String,
        contextLabel: String,
        source: DocumentCandidateSource,
        activityDate: Date,
        hasUnreadUpdate: Bool,
        displayNameMatchRanges: [FuzzyMatchRange] = [],
        contextMatchRanges: [FuzzyMatchRange] = []
    ) {
        self.path = path
        self.displayName = displayName
        self.contextLabel = contextLabel
        self.source = source
        self.activityDate = activityDate
        self.hasUnreadUpdate = hasUnreadUpdate
        self.displayNameMatchRanges = displayNameMatchRanges
        self.contextMatchRanges = contextMatchRanges
    }

    func highlighting(
        displayNameRanges: [FuzzyMatchRange],
        contextRanges: [FuzzyMatchRange]
    ) -> DocumentCandidate {
        DocumentCandidate(
            path: path,
            displayName: displayName,
            contextLabel: contextLabel,
            source: source,
            activityDate: activityDate,
            hasUnreadUpdate: hasUnreadUpdate,
            displayNameMatchRanges: displayNameRanges,
            contextMatchRanges: contextRanges
        )
    }
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
        query: String,
        searchScope: DocumentSearchScope = .global,
        indexedFilesByProject: [String: [WatchedMarkdownFile]] = [:]
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
                contextLabel: contextLabel(
                    for: item.url,
                    projects: projects,
                    scope: searchScope
                ),
                source: .open,
                activityDate: item.lastViewedAt,
                hasUnreadUpdate: unreadByPath[item.path] != nil
            )
        }

        for item in updates where item.readAt == nil && byPath[item.path] == nil {
            byPath[item.path] = DocumentCandidate(
                path: item.path,
                displayName: item.displayName,
                contextLabel: contextLabel(
                    for: item.url,
                    projects: projects,
                    scope: searchScope
                ),
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
                    contextLabel: contextLabel(
                        for: item.url,
                        projects: projects,
                        scope: searchScope
                    ),
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
                contextLabel: contextLabel(
                    for: url,
                    projects: projects,
                    scope: searchScope
                ),
                source: .history,
                activityDate: .distantPast,
                hasUnreadUpdate: unreadByPath[path] != nil
            )
        }

        let terms = query
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)

        if !terms.isEmpty {
            let indexedProjects: [BookmarkItem]
            switch searchScope {
            case .global:
                indexedProjects = projects
            case let .project(project):
                indexedProjects = [project]
            case .unavailableProject:
                indexedProjects = []
            }

            for project in indexedProjects {
                for file in indexedFilesByProject[project.path] ?? []
                    where byPath[file.path] == nil {
                    byPath[file.path] = DocumentCandidate(
                        path: file.path,
                        displayName: file.displayName,
                        contextLabel: contextLabel(
                            for: file.url,
                            projects: projects,
                            scope: searchScope
                        ),
                        source: .project,
                        activityDate: file.modifiedAt,
                        hasUnreadUpdate: unreadByPath[file.path] != nil
                    )
                }
            }
        }

        let scopedCandidates = byPath.values.filter {
            scope(searchScope, contains: $0.url)
        }

        guard !terms.isEmpty else {
            return scopedCandidates
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

        let rankedCandidates = scopedCandidates
            .compactMap { candidate -> (DocumentCandidate, Int)? in
                guard let match = searchMatch(terms: terms, candidate: candidate) else {
                    return nil
                }
                return (
                    candidate.highlighting(
                        displayNameRanges: match.displayNameRanges,
                        contextRanges: match.contextRanges
                    ),
                    match.score
                )
            }
            .sorted { left, right in
                if left.1 != right.1 { return left.1 > right.1 }
                let leftSource = sourceTieBreakScore(left.0, currentPath: currentPath)
                let rightSource = sourceTieBreakScore(right.0, currentPath: currentPath)
                if leftSource != rightSource { return leftSource > rightSource }
                if left.0.activityDate != right.0.activityDate {
                    return left.0.activityDate > right.0.activityDate
                }
                return left.0.displayName.localizedCaseInsensitiveCompare(right.0.displayName)
                    == .orderedAscending
            }
        return Array(rankedCandidates.prefix(100).map(\.0))
    }

    private static func contextLabel(
        for file: URL,
        projects: [BookmarkItem],
        scope: DocumentSearchScope
    ) -> String {
        guard let containingProject = SidebarFileState.containingProject(
            for: file,
            projects: projects
        ) else {
            return [file.deletingLastPathComponent().lastPathComponent, file.lastPathComponent]
                .filter { !$0.isEmpty }
                .joined(separator: " › ")
        }
        switch scope {
        case let .project(scopedProject):
            let relative = MarkdownFolderDiscovery.relativePath(for: file, in: scopedProject.url)
            let relativeComponents = relative.split(separator: "/").map(String.init)
            return relativeComponents.joined(separator: " › ")
        default:
            let relative = MarkdownFolderDiscovery.relativePath(for: file, in: containingProject.url)
            let relativeComponents = relative.split(separator: "/").map(String.init)
            return ([containingProject.displayName] + relativeComponents).joined(separator: " › ")
        }
    }

    private struct CandidateSearchMatch {
        let score: Int
        let displayNameRanges: [FuzzyMatchRange]
        let contextRanges: [FuzzyMatchRange]
    }

    private static func searchMatch(
        terms: [String],
        candidate: DocumentCandidate
    ) -> CandidateSearchMatch? {
        var score = 0
        var filenameTermCount = 0
        var displayNameRanges: [FuzzyMatchRange] = []
        var contextRanges: [FuzzyMatchRange] = []
        let filenameStem = (candidate.displayName as NSString).deletingPathExtension

        for term in terms {
            let filenameSearchText = term.contains(".") ? candidate.displayName : filenameStem
            let filenameMatch = FuzzyMatcher.score(query: term, candidate: filenameSearchText)
            let contextMatch = FuzzyMatcher.score(query: term, candidate: candidate.contextLabel)
            let filenameScore = filenameMatch.map {
                weightedFilenameScore(term: term, candidate: filenameSearchText, fuzzy: $0)
            }
            let contextScore = contextMatch.map {
                weightedContextScore(term: term, candidate: candidate.contextLabel, fuzzy: $0)
            }

            switch (filenameScore, contextScore) {
            case (nil, nil):
                return nil
            case let (.some(filenameScore), .some(contextScore)) where contextScore > filenameScore:
                score += contextScore
                contextRanges.append(contentsOf: contextMatch?.ranges ?? [])
            case let (.some(filenameScore), _):
                score += filenameScore
                filenameTermCount += 1
                displayNameRanges.append(contentsOf: filenameMatch?.ranges ?? [])
            case let (nil, .some(contextScore)):
                score += contextScore
                contextRanges.append(contentsOf: contextMatch?.ranges ?? [])
            }
        }

        return CandidateSearchMatch(
            score: filenameTermCount * 1_000_000 + score,
            displayNameRanges: mergedRanges(displayNameRanges),
            contextRanges: mergedRanges(contextRanges)
        )
    }

    private static func weightedFilenameScore(
        term: String,
        candidate: String,
        fuzzy: FuzzyMatch
    ) -> Int {
        let foldedTerm = folded(term)
        let foldedCandidate = folded(candidate)
        if foldedCandidate == foldedTerm { return 100_000 + fuzzy.score }
        if foldedCandidate.hasPrefix(foldedTerm) { return 50_000 + fuzzy.score }
        if foldedCandidate.contains(foldedTerm) { return 25_000 + fuzzy.score }
        return 10_000 + max(fuzzy.score, 0) * 100
    }

    private static func weightedContextScore(
        term: String,
        candidate: String,
        fuzzy: FuzzyMatch
    ) -> Int {
        let foldedTerm = folded(term)
        let foldedCandidate = folded(candidate)
        if foldedCandidate.hasPrefix(foldedTerm) { return 5_000 + fuzzy.score }
        if foldedCandidate.contains(foldedTerm) { return 2_500 + fuzzy.score }
        return 1_000 + max(fuzzy.score, 0) * 10
    }

    private static func folded(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).lowercased()
    }

    private static func mergedRanges(_ ranges: [FuzzyMatchRange]) -> [FuzzyMatchRange] {
        let indices = Set(ranges.flatMap { range in
            range.start..<(range.start + range.length)
        })
        return indices.sorted().reduce(into: []) { result, index in
            if let last = result.last, index == last.start + last.length {
                result[result.count - 1] = FuzzyMatchRange(
                    start: last.start,
                    length: last.length + 1
                )
            } else {
                result.append(FuzzyMatchRange(start: index, length: 1))
            }
        }
    }

    private static func scope(_ scope: DocumentSearchScope, contains file: URL) -> Bool {
        switch scope {
        case .global:
            true
        case let .project(project):
            SidebarFileState.contains(file: file, in: project.url)
        case .unavailableProject:
            false
        }
    }

    private static func sourceTieBreakScore(
        _ candidate: DocumentCandidate,
        currentPath: String?
    ) -> Int {
        var score: Int
        switch candidate.source {
        case .open: score = 4
        case .update: score = 3
        case .project: score = 2
        case .history: score = 1
        }
        if candidate.hasUnreadUpdate { score += 1 }
        if candidate.path == currentPath { score -= 10 }
        return score
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
