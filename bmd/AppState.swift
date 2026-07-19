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

    private let store: RecentStore
    private var activeScopedURL: URL?

    init(store: RecentStore = .shared) {
        self.store = store
        self.recents = store.loadRecents()
        self.pins = store.loadPins()
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

    func presentPinFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Pin Folder"
        panel.prompt = "Pin"
        if panel.runModal() == .OK, let url = panel.url {
            pinFolder(url)
        }
    }

    func openFile(_ url: URL) {
        let resolved = url.standardizedFileURL

        stopScopedAccess()
        let accessing = resolved.startAccessingSecurityScopedResource()
        if accessing {
            activeScopedURL = resolved
        }

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

    func pinFolder(_ url: URL) {
        pins = store.pinFolder(url.standardizedFileURL)
    }

    func unpin(_ item: BookmarkItem) {
        pins = store.unpin(item)
    }

    func removeRecent(_ item: BookmarkItem) {
        recents = store.removeRecent(item)
    }

    func clearRecents() {
        recents = store.clearRecents()
    }

    func markdownFiles(inFolder item: BookmarkItem) -> [URL] {
        guard let folder = store.resolve(item) else { return [] }
        return store.listMarkdownFiles(in: folder)
    }

    private func stopScopedAccess() {
        if let activeScopedURL {
            activeScopedURL.stopAccessingSecurityScopedResource()
        }
        activeScopedURL = nil
    }
}
