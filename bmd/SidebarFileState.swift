import Foundation

struct WatchedActivityItem: Identifiable, Codable, Hashable {
    let path: String
    let projectPath: String?
    let relativePath: String
    let modifiedAt: Date
    let detectedAt: Date

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var displayName: String { url.lastPathComponent }

    var contextLabel: String {
        if let projectPath {
            let projectName = URL(fileURLWithPath: projectPath).lastPathComponent
            let relativeDirectory = (relativePath as NSString).deletingLastPathComponent
            return relativeDirectory.isEmpty
                ? projectName
                : "\(projectName) / \(relativeDirectory)"
        }
        return url.deletingLastPathComponent().lastPathComponent
    }
}

enum SidebarFileState {
    static let maximumStoredActivity = 100
    static let maximumFilesPerProject = 100

    static func containingProject(
        for file: URL,
        projects: [BookmarkItem]
    ) -> BookmarkItem? {
        projects
            .filter { contains(file: file, in: $0.url) }
            .max { $0.path.count < $1.path.count }
    }

    static func contains(file: URL, in project: URL) -> Bool {
        let filePath = file.standardizedFileURL.path
        let projectPath = project.standardizedFileURL.path
        return filePath.hasPrefix(projectPath + "/")
    }

    static func mergeActivity(
        existing: [WatchedActivityItem],
        changedFiles: [WatchedMarkdownFile],
        detectedAt: Date,
        maximumCount: Int = maximumStoredActivity
    ) -> [WatchedActivityItem] {
        let incoming = changedFiles.map { file in
            WatchedActivityItem(
                path: file.path,
                projectPath: file.rootPath,
                relativePath: file.relativePath,
                modifiedAt: file.modifiedAt,
                detectedAt: detectedAt
            )
        }
        return mergeActivity(
            existing: existing,
            incoming: incoming,
            maximumCount: maximumCount
        )
    }

    static func recordOpenedFile(
        existingActivity: [WatchedActivityItem],
        file: URL,
        project: BookmarkItem?,
        modifiedAt: Date,
        detectedAt: Date,
        maximumCount: Int = maximumStoredActivity
    ) -> [WatchedActivityItem] {
        let relativePath = project.map {
            MarkdownFolderDiscovery.relativePath(for: file, in: $0.url)
        } ?? file.lastPathComponent
        let opened = WatchedActivityItem(
            path: file.standardizedFileURL.path,
            projectPath: project?.path,
            relativePath: relativePath,
            modifiedAt: modifiedAt,
            detectedAt: detectedAt
        )
        return mergeActivity(
            existing: existingActivity,
            incoming: [opened],
            maximumCount: maximumCount
        )
    }

    static func rememberProjectFile(
        existing: [String: [BookmarkItem]],
        file: URL,
        project: BookmarkItem,
        openedAt: Date,
        maximumCount: Int = maximumFilesPerProject
    ) -> [String: [BookmarkItem]] {
        var result = existing
        var projectFiles = result[project.path] ?? []
        let normalizedPath = file.standardizedFileURL.path
        projectFiles.removeAll { $0.path == normalizedPath }
        projectFiles.insert(BookmarkItem.file(file, at: openedAt), at: 0)
        result[project.path] = Array(projectFiles.prefix(maximumCount))
        return result
    }

    static func visibleActivity(
        _ activity: [WatchedActivityItem],
        currentPath: String?,
        maximumCount: Int
    ) -> [WatchedActivityItem] {
        guard maximumCount > 0 else { return [] }
        guard let currentPath,
              let current = activity.first(where: { $0.path == currentPath }) else {
            return Array(activity.prefix(maximumCount))
        }
        let remaining = activity.filter { $0.path != currentPath }
        return [current] + Array(remaining.prefix(maximumCount - 1))
    }

    private static func mergeActivity(
        existing: [WatchedActivityItem],
        incoming: [WatchedActivityItem],
        maximumCount: Int
    ) -> [WatchedActivityItem] {
        let incomingPaths = Set(incoming.map(\.path))
        return Array(
            (incoming + existing.filter { !incomingPaths.contains($0.path) })
                .sorted { left, right in
                    if left.detectedAt != right.detectedAt {
                        return left.detectedAt > right.detectedAt
                    }
                    if left.modifiedAt != right.modifiedAt {
                        return left.modifiedAt > right.modifiedAt
                    }
                    return left.path.localizedCaseInsensitiveCompare(right.path)
                        == .orderedAscending
                }
                .prefix(maximumCount)
        )
    }
}
