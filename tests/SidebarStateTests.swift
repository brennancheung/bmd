import Darwin
import Foundation

@main
enum SidebarStateTests {
    static func main() {
        testProjectMembership()
        testRecentDisplayPaths()
        testOpenedProjectFiles()
        testWatchedActivity()
        print("SidebarStateTests passed")
    }

    private static func testRecentDisplayPaths() {
        let parent = BookmarkItem.folder(URL(fileURLWithPath: "/tmp/work"))
        let nested = BookmarkItem.folder(URL(fileURLWithPath: "/tmp/work/app"))
        let nestedFile = URL(fileURLWithPath: "/tmp/work/app/docs/guide.md")
        let externalFile = URL(fileURLWithPath: "/tmp/notes.md")

        expect(
            SidebarFileState.recentDisplayPath(
                for: nestedFile,
                projects: [parent, nested]
            ) == "app › docs › guide.md",
            "recent paths should use the most specific project and relative path"
        )
        expect(
            SidebarFileState.recentDisplayPath(
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
        expect(state[project.path]?.map(\.path) == [second.path, first.path],
               "projects should contain only explicitly opened files, newest first")
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
            SidebarFileState.visibleActivity(
                merged,
                currentPath: old.path,
                maximumCount: 1
            ).map(\.path) == [old.path],
            "the current file should remain visible even when the watched limit is full"
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
