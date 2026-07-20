import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var currentFile: URL?
    @Published private(set) var markdownText: String = ""
    @Published private(set) var renderToken: UInt64 = 0
    @Published private(set) var statusMessage: String?
    @Published var recents: [BookmarkItem]
    @Published var projects: [BookmarkItem]
    @Published private(set) var watchedActivity: [WatchedActivityItem]
    @Published private(set) var projectFilesByFolder: [String: [BookmarkItem]]

    private let store: RecentStore
    private let sidebarStore: SidebarStateStore
    private let folderWatcher: MarkdownFolderWatcher
    private let currentFileWatcher: CurrentMarkdownFileWatcher
    private var ignoredDirectoryNames = MarkdownFolderDiscovery.defaultIgnoredDirectoryNames

    init(
        store: RecentStore = .shared,
        sidebarStore: SidebarStateStore = .shared,
        folderWatcher: MarkdownFolderWatcher = MarkdownFolderWatcher(),
        currentFileWatcher: CurrentMarkdownFileWatcher = CurrentMarkdownFileWatcher()
    ) {
        self.store = store
        self.sidebarStore = sidebarStore
        self.folderWatcher = folderWatcher
        self.currentFileWatcher = currentFileWatcher
        let loadedRecents = store.loadRecents()
        let loadedProjects = store.loadProjects()
        var loadedProjectFiles = sidebarStore.loadProjectFiles()
        for project in loadedProjects where loadedProjectFiles[project.path] == nil {
            loadedProjectFiles[project.path] = loadedRecents.filter {
                SidebarFileState.contains(file: $0.url, in: project.url)
            }
        }
        recents = loadedRecents
        projects = loadedProjects
        watchedActivity = sidebarStore.loadActivity()
        projectFilesByFolder = loadedProjectFiles
        sidebarStore.saveProjectFiles(loadedProjectFiles)

        folderWatcher.onUpdate = { [weak self] update in
            self?.applyFolderUpdate(update, detectedAt: Date())
        }
        currentFileWatcher.onChange = { [weak self] snapshot in
            self?.applyCurrentFileChange(snapshot, detectedAt: Date())
        }
        folderWatcher.watch(folders: projects.map(\.url), ignoring: ignoredDirectoryNames)
    }

    var currentTitle: String {
        currentFile?.lastPathComponent ?? "bmd"
    }

    var baseDirectory: URL? {
        currentFile?.deletingLastPathComponent()
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var types: [UTType] = [.plainText, .text]
        if let md = UTType(filenameExtension: "md") {
            types.insert(md, at: 0)
        }
        if let markdown = UTType(filenameExtension: "markdown") {
            types.insert(markdown, at: 0)
        }
        panel.allowedContentTypes = types
        panel.allowsOtherFileTypes = true
        panel.title = "Open Markdown"
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            openFile(url)
        }
    }

    func presentAddProjectPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Add Project"
        panel.prompt = "Add"
        if panel.runModal() == .OK, let url = panel.url {
            addProject(url)
        }
    }

    func openFile(_ url: URL) {
        let resolved = url.standardizedFileURL
        let isDifferentFile = currentFile?.path != resolved.path
        guard readFile(resolved) else { return }

        let openedAt = Date()
        recents = store.rememberRecent(resolved, at: openedAt)
        let project = SidebarFileState.containingProject(for: resolved, projects: projects)
        recordWatchedFile(
            resolved,
            project: project,
            modifiedAt: fileModificationDate(resolved) ?? openedAt,
            detectedAt: openedAt
        )
        if let project {
            projectFilesByFolder = SidebarFileState.rememberProjectFile(
                existing: projectFilesByFolder,
                file: resolved,
                project: project,
                openedAt: openedAt
            )
            sidebarStore.saveProjectFiles(projectFilesByFolder)
        }

        if isDifferentFile {
            currentFileWatcher.watch(file: resolved)
        }
    }

    func openRecent(_ item: BookmarkItem) {
        if let url = store.resolve(item) {
            openFile(url)
        } else {
            statusMessage = "Could not open \(item.displayName)"
            recents = store.loadRecents()
        }
    }

    func openWatched(_ item: WatchedActivityItem) {
        openFile(item.url)
    }

    func addProject(_ url: URL) {
        let normalized = url.standardizedFileURL
        projects = store.addProject(normalized)
        guard let project = projects.first(where: { $0.path == normalized.path }) else { return }

        if projectFilesByFolder[project.path] == nil {
            projectFilesByFolder[project.path] = recents.filter {
                SidebarFileState.contains(file: $0.url, in: project.url)
            }
            sidebarStore.saveProjectFiles(projectFilesByFolder)
        }
        restartFolderWatcher()
    }

    func removeProject(_ item: BookmarkItem) {
        projects = store.removeProject(item)
        projectFilesByFolder[item.path] = nil
        sidebarStore.saveProjectFiles(projectFilesByFolder)
        restartFolderWatcher()
    }

    func removeRecent(_ item: BookmarkItem) {
        recents = store.removeRecent(item)
    }

    func clearRecents() {
        recents = store.clearRecents()
    }

    func projectFiles(in project: BookmarkItem) -> [BookmarkItem] {
        projectFilesByFolder[project.path] ?? []
    }

    func watchedFiles(limit: Int) -> [WatchedActivityItem] {
        SidebarFileState.visibleActivity(
            watchedActivity,
            currentPath: currentFile?.path,
            maximumCount: limit
        )
    }

    func refreshProjects() {
        folderWatcher.refresh()
    }

    func updateWatchConfiguration(ignoredDirectoryNames: Set<String>) {
        let normalized = Set(ignoredDirectoryNames.map { $0.lowercased() })
        guard normalized != self.ignoredDirectoryNames else { return }
        self.ignoredDirectoryNames = normalized
        restartFolderWatcher()
    }

    private func restartFolderWatcher() {
        folderWatcher.watch(
            folders: projects.map(\.url),
            ignoring: ignoredDirectoryNames
        )
    }

    @discardableResult
    private func readFile(_ url: URL) -> Bool {
        do {
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else {
                statusMessage = "Could not decode \(url.lastPathComponent)"
                return false
            }
            currentFile = url
            markdownText = text
            renderToken &+= 1
            statusMessage = nil
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    private func applyFolderUpdate(_ update: WatchedFolderUpdate, detectedAt: Date) {
        guard projects.contains(where: { $0.path == update.rootPath }),
              !update.isInitial,
              !update.changedFiles.isEmpty else {
            return
        }
        watchedActivity = SidebarFileState.mergeActivity(
            existing: watchedActivity,
            changedFiles: update.changedFiles,
            detectedAt: detectedAt
        )
        sidebarStore.saveActivity(watchedActivity)
    }

    private func applyCurrentFileChange(
        _ snapshot: MarkdownFileSnapshot,
        detectedAt: Date
    ) {
        guard currentFile?.path == snapshot.path else { return }
        let project = SidebarFileState.containingProject(
            for: snapshot.url,
            projects: projects
        )
        recordWatchedFile(
            snapshot.url,
            project: project,
            modifiedAt: snapshot.modifiedAt,
            detectedAt: detectedAt
        )
        _ = readFile(snapshot.url)
    }

    private func recordWatchedFile(
        _ file: URL,
        project: BookmarkItem?,
        modifiedAt: Date,
        detectedAt: Date
    ) {
        watchedActivity = SidebarFileState.recordOpenedFile(
            existingActivity: watchedActivity,
            file: file,
            project: project,
            modifiedAt: modifiedAt,
            detectedAt: detectedAt
        )
        sidebarStore.saveActivity(watchedActivity)
    }

    private func fileModificationDate(_ file: URL) -> Date? {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
    }
}
