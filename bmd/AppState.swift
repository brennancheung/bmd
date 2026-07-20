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
    @Published private(set) var openDocuments: [OpenDocumentItem]
    @Published var projects: [BookmarkItem]
    @Published private(set) var watchedActivity: [WatchedActivityItem]
    @Published private(set) var projectFilesByFolder: [String: [BookmarkItem]]
    @Published private(set) var history: DocumentHistoryState
    @Published var isQuickSwitcherPresented = false

    private let store: RecentStore
    private let sidebarStore: SidebarStateStore
    private let folderWatcher: MarkdownFolderWatcher
    private let currentFileWatcher: CurrentMarkdownFileWatcher
    private var ignoredDirectoryNames = MarkdownFolderDiscovery.defaultIgnoredDirectoryNames

    private enum HistoryBehavior: Equatable {
        case record
        case preservePosition
    }

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
        let loadedOpenDocuments = store.loadOpenDocuments()
        let loadedProjects = store.loadProjects()
        var loadedProjectFiles = sidebarStore.loadProjectFiles()
        for project in loadedProjects where loadedProjectFiles[project.path] == nil {
            let migratedItems = loadedOpenDocuments.isEmpty
                ? loadedRecents
                : loadedOpenDocuments.map {
                    BookmarkItem.file($0.url, at: $0.lastViewedAt)
                }
            loadedProjectFiles[project.path] = migratedItems.filter {
                SidebarFileState.contains(file: $0.url, in: project.url)
            }
        }
        openDocuments = loadedOpenDocuments
        projects = loadedProjects
        watchedActivity = sidebarStore.loadActivity()
        projectFilesByFolder = loadedProjectFiles
        history = sidebarStore.loadHistory()
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

    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }

    func presentOpenPanel() {
        presentOpenPanel(startingAt: nil, restrictToMarkdown: false)
    }

    func presentProjectMarkdownPanel(_ project: BookmarkItem) {
        presentOpenPanel(startingAt: project.url, restrictToMarkdown: true)
    }

    private func presentOpenPanel(
        startingAt directory: URL?,
        restrictToMarkdown: Bool
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let markdownTypes = MarkdownFolderDiscovery.supportedExtensions
            .sorted()
            .compactMap { UTType(filenameExtension: $0) }
        panel.allowedContentTypes = restrictToMarkdown
            ? markdownTypes
            : markdownTypes + [.plainText, .text]
        panel.allowsOtherFileTypes = !restrictToMarkdown
        panel.directoryURL = directory?.standardizedFileURL
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
        openFile(url, historyBehavior: .record)
    }

    private func openFile(_ url: URL, historyBehavior: HistoryBehavior) {
        let resolved = url.standardizedFileURL
        let isDifferentFile = currentFile?.path != resolved.path
        guard readFile(resolved) else { return }

        let openedAt = Date()
        openDocuments = DocumentNavigation.rememberOpen(
            resolved,
            in: openDocuments,
            at: openedAt
        )
        store.saveOpenDocuments(openDocuments)
        markUpdateRead(path: resolved.path, at: openedAt)
        if historyBehavior == .record {
            history.record(resolved.path)
            sidebarStore.saveHistory(history)
        }
        let project = SidebarFileState.containingProject(for: resolved, projects: projects)
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

    func openDocument(_ item: OpenDocumentItem) {
        if FileManager.default.fileExists(atPath: item.path) {
            openFile(item.url)
        } else {
            statusMessage = "Could not open \(item.displayName)"
            closeOpenDocument(item)
        }
    }

    func openBookmark(_ item: BookmarkItem) {
        if let url = store.resolve(item) {
            openFile(url)
        } else {
            statusMessage = "Could not open \(item.displayName)"
        }
    }

    func openUpdate(_ item: WatchedActivityItem) {
        openFile(item.url)
    }

    func addProject(_ url: URL) {
        let normalized = url.standardizedFileURL
        projects = store.addProject(normalized)
        guard let project = projects.first(where: { $0.path == normalized.path }) else { return }

        if projectFilesByFolder[project.path] == nil {
            projectFilesByFolder[project.path] = openDocuments
                .filter { SidebarFileState.contains(file: $0.url, in: project.url) }
                .map { BookmarkItem.file($0.url, at: $0.lastViewedAt) }
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

    func closeOpenDocument(_ item: OpenDocumentItem) {
        let replacement = DocumentNavigation.replacementAfterClosing(
            path: item.path,
            in: openDocuments
        )
        openDocuments.removeAll { $0.path == item.path }
        store.saveOpenDocuments(openDocuments)

        guard currentFile?.path == item.path else { return }
        if let replacement {
            openFile(replacement.url, historyBehavior: .record)
        } else {
            currentFile = nil
            markdownText = ""
            renderToken &+= 1
            currentFileWatcher.stop()
        }
    }

    func closeUnpinnedDocuments() {
        let currentPath = currentFile?.path
        openDocuments.removeAll { !$0.isPinned && $0.path != currentPath }
        store.saveOpenDocuments(openDocuments)
    }

    func togglePin(_ item: OpenDocumentItem) {
        openDocuments = DocumentNavigation.togglePin(
            path: item.path,
            in: openDocuments
        )
        store.saveOpenDocuments(openDocuments)
    }

    func moveOpenDocument(_ item: OpenDocumentItem, by offset: Int) {
        openDocuments = DocumentNavigation.move(
            path: item.path,
            by: offset,
            in: openDocuments
        )
        store.saveOpenDocuments(openDocuments)
    }

    func openDocument(atShortcutPosition position: Int) {
        guard let item = DocumentNavigation.document(
            atShortcutPosition: position,
            in: openDocuments
        ) else { return }
        openDocument(item)
    }

    func selectAdjacentOpenDocument(_ direction: OpenDocumentTraversalDirection) {
        guard openDocuments.count > 1,
              let item = DocumentNavigation.adjacentDocument(
                to: currentFile?.path,
                direction: direction,
                in: openDocuments
              ) else { return }
        openDocument(item)
    }

    func projectFiles(in project: BookmarkItem) -> [BookmarkItem] {
        projectFilesByFolder[project.path] ?? []
    }

    func documentDisplayPath(_ item: OpenDocumentItem) -> String {
        SidebarFileState.documentDisplayPath(for: item.url, projects: projects)
    }

    func updates(limit: Int) -> [WatchedActivityItem] {
        SidebarFileState.visibleUpdates(
            watchedActivity.filter { FileManager.default.fileExists(atPath: $0.path) },
            openPaths: Set(openDocuments.map(\.path)),
            maximumCount: limit
        )
    }

    func unreadUpdate(for path: String) -> WatchedActivityItem? {
        SidebarFileState.unreadUpdate(for: path, in: watchedActivity)
    }

    func quickSwitcherCandidates(query: String) -> [DocumentCandidate] {
        DocumentNavigation.candidates(
            openDocuments: openDocuments,
            updates: watchedActivity,
            projects: projects,
            projectFilesByFolder: projectFilesByFolder,
            history: history,
            currentPath: currentFile?.path,
            query: query
        ).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func showQuickSwitcher() {
        isQuickSwitcherPresented = true
    }

    func goBack() {
        navigateHistory(backward: true)
    }

    func goForward() {
        navigateHistory(backward: false)
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
        recordFileUpdate(
            snapshot.url,
            project: project,
            modifiedAt: snapshot.modifiedAt,
            detectedAt: detectedAt
        )
        _ = readFile(snapshot.url)
    }

    private func recordFileUpdate(
        _ file: URL,
        project: BookmarkItem?,
        modifiedAt: Date,
        detectedAt: Date
    ) {
        watchedActivity = SidebarFileState.recordFileUpdate(
            existingActivity: watchedActivity,
            file: file,
            project: project,
            modifiedAt: modifiedAt,
            detectedAt: detectedAt
        )
        sidebarStore.saveActivity(watchedActivity)
    }

    private func markUpdateRead(path: String, at date: Date) {
        let updated = SidebarFileState.markRead(
            path: path,
            in: watchedActivity,
            at: date
        )
        guard updated != watchedActivity else { return }
        watchedActivity = updated
        sidebarStore.saveActivity(watchedActivity)
    }

    private func navigateHistory(backward: Bool) {
        var nextHistory = history
        while let path = backward ? nextHistory.goBack() : nextHistory.goForward() {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            history = nextHistory
            sidebarStore.saveHistory(history)
            openFile(
                URL(fileURLWithPath: path),
                historyBehavior: .preservePosition
            )
            return
        }
        history = nextHistory
        sidebarStore.saveHistory(history)
    }

}
