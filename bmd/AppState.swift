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
    @Published private(set) var indexedFilesByProject: [String: [WatchedMarkdownFile]]
    @Published private(set) var history: DocumentHistoryState
    @Published private(set) var editorWorkspace = EditorWorkspaceState()
    @Published var isQuickSwitcherPresented = false
    @Published private(set) var quickSwitcherScope: DocumentSearchScope = .global

    private let store: RecentStore
    private let sidebarStore: SidebarStateStore
    private let folderWatcher: MarkdownFolderWatcher
    private let currentFileWatcher: CurrentMarkdownFileWatcher
    private var scanConfiguration = MarkdownScanConfiguration.default
    private var recentSelfSaves: [String: (text: String, savedAt: Date)] = [:]

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
        indexedFilesByProject = [:]
        history = sidebarStore.loadHistory()
        sidebarStore.saveProjectFiles(loadedProjectFiles)

        folderWatcher.onUpdate = { [weak self] update in
            self?.applyFolderUpdate(update, detectedAt: Date())
        }
        currentFileWatcher.onChange = { [weak self] snapshot in
            self?.applyCurrentFileChange(snapshot, detectedAt: Date())
        }
        folderWatcher.watch(
            folders: projects.map(\.url),
            configuration: scanConfiguration
        )
    }

    var currentTitle: String {
        currentFile?.lastPathComponent ?? "bmd"
    }

    var baseDirectory: URL? {
        currentFile?.deletingLastPathComponent()
    }

    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }
    var isEditing: Bool { editorWorkspace.mode == .editing }
    var hasUnsavedEdits: Bool { !editorWorkspace.dirtyPaths.isEmpty }
    var editorRevision: UInt64 { editorWorkspace.revision }
    var editorText: String {
        guard let path = currentFile?.path else { return "" }
        return editorWorkspace.text(for: path, fallback: markdownText)
    }
    var currentEditIsDirty: Bool {
        guard let path = currentFile?.path else { return false }
        return editorWorkspace.isDirty(path: path)
    }
    var currentEditHasConflict: Bool {
        guard let path = currentFile?.path else { return false }
        return editorWorkspace.buffer(for: path)?.hasExternalConflict == true
    }
    var currentProject: BookmarkItem? {
        guard let currentFile else { return nil }
        return SidebarFileState.containingProject(for: currentFile, projects: projects)
    }

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

        if isDifferentFile {
            editorWorkspace.showPreview()
        }

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

    func beginEditingCurrentDocument() {
        guard let currentFile else { return }
        editorWorkspace.beginEditing(
            path: currentFile.path,
            diskText: markdownText
        )
        statusMessage = nil
    }

    func updateCurrentEditBuffer(_ text: String) {
        guard let currentFile, isEditing else { return }
        editorWorkspace.updateBuffer(
            path: currentFile.path,
            text: text,
            diskText: markdownText
        )
    }

    func saveCurrentEdit(returnToPreview: Bool = false, overwriteConflict: Bool = false) {
        guard let currentFile,
              let buffer = editorWorkspace.buffer(for: currentFile.path) else {
            return
        }
        guard overwriteConflict || !buffer.hasExternalConflict else {
            statusMessage = "This file changed on disk. Choose which version to keep before saving."
            return
        }

        do {
            recentSelfSaves[currentFile.path] = (buffer.text, Date())
            try Data(buffer.text.utf8).write(to: currentFile, options: .atomic)
            editorWorkspace.markSaved(path: currentFile.path, text: buffer.text)
            markdownText = buffer.text
            renderToken &+= 1
            statusMessage = nil
            if returnToPreview {
                editorWorkspace.showPreview()
            }
        } catch {
            recentSelfSaves[currentFile.path] = nil
            statusMessage = "Could not save \(currentFile.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func returnToPreviewIfClean() {
        guard currentEditIsDirty else {
            editorWorkspace.showPreview()
            statusMessage = nil
            return
        }
        statusMessage = "Save the document before returning to Preview."
    }

    func reloadCurrentEditFromDisk() {
        guard let currentFile else { return }
        editorWorkspace.reloadFromDisk(path: currentFile.path, text: markdownText)
        statusMessage = nil
    }

    func hasUnsavedEdit(for path: String) -> Bool {
        editorWorkspace.isDirty(path: path)
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
        indexedFilesByProject[item.path] = nil
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
            query: query,
            searchScope: quickSwitcherScope,
            indexedFilesByProject: indexedFilesByProject
        ).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func showQuickSwitcher() {
        showGlobalSearch()
    }

    func showGlobalSearch() {
        quickSwitcherScope = .global
        isQuickSwitcherPresented = true
    }

    func showProjectSearch(_ project: BookmarkItem) {
        quickSwitcherScope = .project(project)
        isQuickSwitcherPresented = true
    }

    func showCurrentProjectSearch() {
        if let currentProject {
            showProjectSearch(currentProject)
        } else {
            quickSwitcherScope = .unavailableProject(currentFile)
            isQuickSwitcherPresented = true
        }
    }

    func addCurrentDocumentFolderAsProject() {
        guard case let .unavailableProject(file?) = quickSwitcherScope else { return }
        let directory = file.deletingLastPathComponent()
        addProject(directory)
        if let project = projects.first(where: { $0.path == directory.standardizedFileURL.path }) {
            quickSwitcherScope = .project(project)
        }
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

    func updateWatchConfiguration(
        ignoredPatterns: [String],
        usesGitIgnoreFiles: Bool
    ) {
        let configuration = MarkdownScanConfiguration(
            customPatterns: ignoredPatterns,
            usesGitIgnoreFiles: usesGitIgnoreFiles
        )
        guard configuration != scanConfiguration else { return }
        scanConfiguration = configuration
        restartFolderWatcher()
    }

    private func restartFolderWatcher() {
        folderWatcher.watch(
            folders: projects.map(\.url),
            configuration: scanConfiguration
        )
    }

    @discardableResult
    private func readFile(_ url: URL) -> Bool {
        do {
            let text = try readText(from: url)
            currentFile = url
            markdownText = text
            _ = editorWorkspace.observeDiskText(path: url.path, text: text)
            renderToken &+= 1
            statusMessage = nil
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    private func applyFolderUpdate(_ update: WatchedFolderUpdate, detectedAt: Date) {
        guard projects.contains(where: { $0.path == update.rootPath }) else {
            return
        }
        indexedFilesByProject[update.rootPath] = update.files
        let externallyChangedFiles = update.changedFiles.filter {
            !isRecentSelfSave($0.url, detectedAt: detectedAt)
        }
        guard
            !update.isInitial,
            !externallyChangedFiles.isEmpty else {
            return
        }
        watchedActivity = SidebarFileState.mergeActivity(
            existing: watchedActivity,
            changedFiles: externallyChangedFiles,
            detectedAt: detectedAt
        )
        sidebarStore.saveActivity(watchedActivity)
    }

    private func applyCurrentFileChange(
        _ snapshot: MarkdownFileSnapshot,
        detectedAt: Date
    ) {
        guard currentFile?.path == snapshot.path else { return }
        guard let text = try? readText(from: snapshot.url) else {
            statusMessage = "Could not reload \(snapshot.url.lastPathComponent)"
            return
        }
        if isRecentSelfSave(snapshot.url, detectedAt: detectedAt, knownText: text) {
            markdownText = text
            _ = editorWorkspace.observeDiskText(path: snapshot.path, text: text)
            renderToken &+= 1
            return
        }
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
        markdownText = text
        _ = editorWorkspace.observeDiskText(path: snapshot.path, text: text)
        renderToken &+= 1
        statusMessage = nil
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

    private func readText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) {
            return text
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    private func isRecentSelfSave(
        _ file: URL,
        detectedAt: Date,
        knownText: String? = nil
    ) -> Bool {
        let path = file.standardizedFileURL.path
        recentSelfSaves = recentSelfSaves.filter {
            detectedAt.timeIntervalSince($0.value.savedAt) < 5
        }
        guard let saved = recentSelfSaves[path] else { return false }
        let diskText = knownText ?? (try? readText(from: file))
        return diskText == saved.text
    }

}
