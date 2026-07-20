import Darwin
import Foundation

@main
enum FolderWatcherTests {
    @MainActor
    static func main() async throws {
        try testRecursiveScanner()
        testChangeDetection()
        try await testWatcherRefresh()
        print("FolderWatcherTests passed")
    }

    private static func testRecursiveScanner() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("bmd-folder-watcher-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: root) }

        let nested = root.appendingPathComponent("docs/nested", isDirectory: true)
        let hidden = root.appendingPathComponent(".hidden", isDirectory: true)
        let nodeModules = root.appendingPathComponent("node_modules/package", isDirectory: true)
        try manager.createDirectory(at: nested, withIntermediateDirectories: true)
        try manager.createDirectory(at: hidden, withIntermediateDirectories: true)
        try manager.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try Data("root".utf8).write(to: root.appendingPathComponent("README.md"))
        try Data("nested".utf8).write(to: nested.appendingPathComponent("plan.markdown"))
        try Data("ignore".utf8).write(to: nested.appendingPathComponent("notes.txt"))
        try Data("hidden".utf8).write(to: hidden.appendingPathComponent("secret.md"))
        try Data("dependency".utf8).write(to: nodeModules.appendingPathComponent("README.md"))

        let files = MarkdownFolderScanner().scan(root)
        expect(
            files.map(\.relativePath) == ["docs/nested/plan.markdown", "README.md"],
            "the scanner should recurse while skipping node_modules, hidden, and non-Markdown files"
        )
        expect(files.allSatisfy { $0.rootPath == root.standardizedFileURL.path },
               "every result should retain its watched-folder identity")
    }

    private static func testChangeDetection() {
        let root = "/tmp/project"
        let old = file(root: root, relative: "old.md", modified: 1, size: 10)
        let updated = file(root: root, relative: "old.md", modified: 2, size: 11)
        let unchanged = file(root: root, relative: "same.md", modified: 1, size: 10)
        let new = file(root: root, relative: "new.md", modified: 3, size: 5)

        let changed = MarkdownFolderDiscovery.changedFiles(
            previous: [old, unchanged],
            current: [updated, unchanged, new]
        )
        expect(changed.map(\.relativePath) == ["new.md", "old.md"],
               "new and modified files should surface newest-first without unchanged files")
    }

    @MainActor
    private static func testWatcherRefresh() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("bmd-folder-stream-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let watcher = MarkdownFolderWatcher()
        var updates: [WatchedFolderUpdate] = []
        watcher.onUpdate = { update in
            updates.append(update)
        }
        watcher.watch(folders: [root])

        try await Task.sleep(nanoseconds: 200_000_000)
        expect(updates.first?.isInitial == true,
               "starting a watcher should publish its initial folder snapshot")

        let newFile = root.appendingPathComponent("agent-output.md")
        try Data("new output".utf8).write(to: newFile)
        watcher.refresh()

        for _ in 0..<20 where !updates.contains(where: {
            $0.changedFiles.contains { $0.path == newFile.path }
        }) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        expect(
            updates.contains(where: {
                $0.changedFiles.contains { $0.path == newFile.path }
            }),
            "a newly written Markdown file should be published as folder activity"
        )
    }

    private static func file(
        root: String,
        relative: String,
        modified: TimeInterval,
        size: Int
    ) -> WatchedMarkdownFile {
        WatchedMarkdownFile(
            rootPath: root,
            path: root + "/" + relative,
            relativePath: relative,
            modifiedAt: Date(timeIntervalSince1970: modified),
            byteSize: size
        )
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            FileHandle.standardError.write(Data("Test failed: \(message)\n".utf8))
            Darwin.exit(EXIT_FAILURE)
        }
    }
}
