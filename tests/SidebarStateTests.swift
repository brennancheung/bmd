import Darwin
import Foundation

@main
enum SidebarStateTests {
    static func main() {
        testProjectMembership()
        testRecentDisplayPaths()
        testOpenedProjectFiles()
        testWatchedActivity()
        testLegacyActivityMigration()
        print("SidebarStateTests passed")
    }

    private static func testRecentDisplayPaths() {
        let parent = BookmarkItem.folder(URL(fileURLWithPath: "/tmp/work"))
        let nested = BookmarkItem.folder(URL(fileURLWithPath: "/tmp/work/app"))
        let nestedFile = URL(fileURLWithPath: "/tmp/work/app/docs/guide.md")
        let externalFile = URL(fileURLWithPath: "/tmp/notes.md")

        expect(
            SidebarFileState.documentDisplayPath(
                for: nestedFile,
                projects: [parent, nested]
            ) == "app › docs › guide.md",
            "recent paths should use the most specific project and relative path"
        )
        expect(
            SidebarFileState.documentDisplayPath(
                for: externalFile,
                projects: [parent, nested]
            ) == "notes.md",
            "recent paths outside projects should keep the filename"
        )
    }

    private static func testProjectMembership() {
        let parent = BookmarkItem.folder(URL(fileURLWithPath: "/tmp/work"))
        let nested = BookmarkItem.folder(URL(fileURLWithPath: "/tmp/work/app"))
        let file = URL(fileURLWithPath: "/tmp/work/app/README.md")

        expect(
            SidebarFileState.containingProject(for: file, projects: [parent, nested]) == nested,
            "the most specific containing project should own an opened file"
        )
        expect(
            !SidebarFileState.contains(
                file: URL(fileURLWithPath: "/tmp/workspace/README.md"),
                in: parent.url
            ),
            "similar path prefixes must not count as project membership"
        )
    }

    private static func testOpenedProjectFiles() {
        let project = BookmarkItem.folder(URL(fileURLWithPath: "/tmp/project"))
        let first = URL(fileURLWithPath: "/tmp/project/first.md")
        let second = URL(fileURLWithPath: "/tmp/project/docs/second.md")
        var state: [String: [BookmarkItem]] = [:]

        state = SidebarFileState.rememberProjectFile(
            existing: state,
            file: first,
            project: project,
            openedAt: Date(timeIntervalSince1970: 1)
        )
        state = SidebarFileState.rememberProjectFile(
            existing: state,
            file: second,
            project: project,
            openedAt: Date(timeIntervalSince1970: 2)
        )
        expect(state[project.path]?.map(\.path) == [first.path, second.path],
               "projects should contain only explicitly opened files in stable order")
    }

    private static func testWatchedActivity() {
        let root = "/tmp/project"
        let old = WatchedMarkdownFile(
            rootPath: root,
            path: root + "/old.md",
            relativePath: "old.md",
            modifiedAt: Date(timeIntervalSince1970: 1),
            byteSize: 1
        )
        let new = WatchedMarkdownFile(
            rootPath: root,
            path: root + "/new.md",
            relativePath: "new.md",
            modifiedAt: Date(timeIntervalSince1970: 2),
            byteSize: 2
        )
        let initial = SidebarFileState.mergeActivity(
            existing: [],
            changedFiles: [old],
            detectedAt: Date(timeIntervalSince1970: 10)
        )
        let merged = SidebarFileState.mergeActivity(
            existing: initial,
            changedFiles: [new, old],
            detectedAt: Date(timeIntervalSince1970: 20)
        )

        expect(merged.map(\.path) == [new.path, old.path],
               "watched activity should be newest-first and deduplicate paths")
        expect(merged.first?.contextLabel == "project",
               "watched rows should identify their project without showing the full path")
        expect(
            SidebarFileState.visibleUpdates(
                merged,
                openPaths: [old.path],
                maximumCount: 1
            ).map(\.path) == [new.path],
            "open documents should show update state in place instead of duplicating rows"
        )
    }

    private static func testLegacyActivityMigration() {
        let suiteName = "bmd-sidebar-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fail("could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("bmd-legacy-activity-\(UUID().uuidString).md")
        _ = FileManager.default.createFile(atPath: file.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: file) }
        let item = WatchedActivityItem(
            path: file.path,
            projectPath: nil,
            relativePath: file.lastPathComponent,
            modifiedAt: Date(timeIntervalSince1970: 1),
            detectedAt: Date(timeIntervalSince1970: 2),
            readAt: nil
        )
        defaults.set(try? JSONEncoder().encode([item]), forKey: "bmd.watchedActivity")

        let migrated = SidebarStateStore(defaults: defaults).loadActivity()
        expect(migrated.first?.readAt != nil,
               "legacy watched activity should migrate as read instead of flooding Updates")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("Test failed: \(message)\n".utf8))
        Darwin.exit(EXIT_FAILURE)
    }
}
