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
    @Published var pins: [BookmarkItem]
    @Published private(set) var watchedFilesByFolder: [String: [WatchedMarkdownFile]] = [:]
    @Published private(set) var folderActivityByFolder: [String: [WatchedMarkdownFile]] = [:]

    private let store: RecentStore
    private let folderWatcher: MarkdownFolderWatcher

    init(
        store: RecentStore = .shared,
        folderWatcher: MarkdownFolderWatcher = MarkdownFolderWatcher()
    ) {
        self.store = store
        self.folderWatcher = folderWatcher
        self.recents = store.loadRecents()
        self.pins = store.loadPins()
        folderWatcher.onUpdate = { [weak self] update in
            self?.applyFolderUpdate(update)
        }
        folderWatcher.watch(folders: pins.map(\.url))
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

    func presentAddFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Add Folder"
        panel.prompt = "Add"
        if panel.runModal() == .OK, let url = panel.url {
            addFolder(url)
        }
    }

    func openFile(_ url: URL) {
        let resolved = url.standardizedFileURL

        do {
            let data = try Data(contentsOf: resolved)
            guard let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else {
                statusMessage = "Could not decode \(resolved.lastPathComponent)"
                return
            }

            currentFile = resolved
            markdownText = text
            renderToken &+= 1
            statusMessage = nil

            recents = store.rememberRecent(resolved)
            clearFolderActivity(for: resolved)
        } catch {
            statusMessage = error.localizedDescription
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

    func addFolder(_ url: URL) {
        pins = store.pinFolder(url.standardizedFileURL)
        folderWatcher.watch(folders: pins.map(\.url))
    }

    func removeFolder(_ item: BookmarkItem) {
        pins = store.unpin(item)
        watchedFilesByFolder[item.path] = nil
        folderActivityByFolder[item.path] = nil
        folderWatcher.watch(folders: pins.map(\.url))
    }

    func removeRecent(_ item: BookmarkItem) {
        recents = store.removeRecent(item)
    }

    func clearRecents() {
        recents = store.clearRecents()
    }

    func watchedFiles(in folder: BookmarkItem) -> [WatchedMarkdownFile] {
        watchedFilesByFolder[folder.path] ?? []
    }

    func folderActivity(in folder: BookmarkItem) -> [WatchedMarkdownFile] {
        folderActivityByFolder[folder.path] ?? []
    }

    func refreshFolders() {
        folderWatcher.refresh()
    }

    private func applyFolderUpdate(_ update: WatchedFolderUpdate) {
        guard pins.contains(where: { $0.path == update.rootPath }) else { return }
        watchedFilesByFolder[update.rootPath] = update.files
        guard !update.isInitial, !update.changedFiles.isEmpty else { return }

        let changedPaths = Set(update.changedFiles.map(\.path))
        let currentPaths = Set(update.files.map(\.path))
        let existing = (folderActivityByFolder[update.rootPath] ?? [])
            .filter { currentPaths.contains($0.path) && !changedPaths.contains($0.path) }
        folderActivityByFolder[update.rootPath] = Array(
            (update.changedFiles + existing).prefix(20)
        )
    }

    private func clearFolderActivity(for file: URL) {
        let path = file.standardizedFileURL.path
        for rootPath in Array(folderActivityByFolder.keys) {
            folderActivityByFolder[rootPath]?.removeAll { $0.path == path }
        }
    }
}
