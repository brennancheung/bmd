import Darwin
import Foundation

@main
enum FolderWatcherTests {
    @MainActor
    static func main() async throws {
        try testRecursiveScanner()
        try testCustomGlobPatterns()
        try testNestedGitIgnoreRules()
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

    private static func testCustomGlobPatterns() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("bmd-custom-globs-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: root) }

        let docs = root.appendingPathComponent("docs", isDirectory: true)
        let generated = root.appendingPathComponent("Generated", isDirectory: true)
        let cache = root.appendingPathComponent("cache/nested", isDirectory: true)
        try manager.createDirectory(at: docs, withIntermediateDirectories: true)
        try manager.createDirectory(at: generated, withIntermediateDirectories: true)
        try manager.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data().write(to: docs.appendingPathComponent("notes.draft.md"))
        try Data().write(to: docs.appendingPathComponent("notes.final.md"))
        try Data().write(to: docs.appendingPathComponent("temp1.md"))
        try Data().write(to: docs.appendingPathComponent("apple.md"))
        try Data().write(to: generated.appendingPathComponent("output.md"))
        try Data().write(to: cache.appendingPathComponent("cached.md"))

        let configuration = MarkdownScanConfiguration(
            customPatterns: [
                "generated",
                "**/*.draft.md",
                "cache/**",
                "docs/temp?.md",
                "docs/[ab]*.md",
            ],
            usesGitIgnoreFiles: false
        )
        let files = MarkdownFolderScanner().scan(root, configuration: configuration)
        expect(
            files.map(\.relativePath) == ["docs/notes.final.md"],
            "custom ignores should support names, *, **, ?, and character-class globs"
        )
    }

    private static func testNestedGitIgnoreRules() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("bmd-gitignore-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: root) }

        let docs = root.appendingPathComponent("docs", isDirectory: true)
        let nested = docs.appendingPathComponent("nested", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        let other = root.appendingPathComponent("other", isDirectory: true)
        for directory in [nested, cache, other] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        try Data("""
        root-only.md
        cache/
        *.draft.md
        !keep.draft.md
        /docs/rooted.md
        """.utf8).write(to: root.appendingPathComponent(".gitignore"))
        try Data("""
        *.md
        !visible.md
        """.utf8).write(to: docs.appendingPathComponent(".gitignore"))
        try Data("!revived.md\n".utf8).write(
            to: nested.appendingPathComponent(".gitignore")
        )
        try Data("!hidden.md\n".utf8).write(
            to: cache.appendingPathComponent(".gitignore")
        )

        let paths = [
            "README.md",
            "root-only.md",
            "discard.draft.md",
            "keep.draft.md",
            "cache/hidden.md",
            "docs/rooted.md",
            "docs/hidden.md",
            "docs/visible.md",
            "docs/nested/revived.md",
            "docs/nested/other.md",
            "other/rooted.md",
        ]
        for path in paths {
            try Data().write(to: root.appendingPathComponent(path))
        }

        let files = MarkdownFolderScanner().scan(root)
        expect(
            files.map(\.relativePath) == [
                "docs/nested/revived.md",
                "docs/visible.md",
                "keep.draft.md",
                "other/rooted.md",
                "README.md",
            ],
            "root and nested .gitignore rules should compose with negation and rooted patterns"
        )

        let withoutGitIgnore = MarkdownFolderScanner().scan(
            root,
            configuration: MarkdownScanConfiguration(
                customPatterns: [],
                usesGitIgnoreFiles: false
            )
        )
        expect(
            withoutGitIgnore.map(\.relativePath) == paths.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            },
            "disabling .gitignore support should leave ordinary Markdown files indexed"
        )
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
