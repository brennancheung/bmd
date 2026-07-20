import Darwin
import Foundation

@main
enum AppStateIntegrationTests {
    @MainActor
    static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("bmd-app-state-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let suiteName = "bmd-app-state-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fail("could not create isolated UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let opened = root.appendingPathComponent("opened.md")
        let unopened = root.appendingPathComponent("unopened.md")
        try Data("first version".utf8).write(to: opened)
        try Data("never opened".utf8).write(to: unopened)

        let state = AppState(
            store: RecentStore(defaults: defaults),
            sidebarStore: SidebarStateStore(defaults: defaults)
        )
        state.addProject(root)
        state.openFile(opened)

        guard let project = state.projects.first else {
            fail("adding a project should persist it")
        }
        expect(state.projectFiles(in: project).map(\.path) == [opened.path],
               "a project should show the opened file but not every Markdown file")
        expect(state.openDocuments.first?.path == opened.path,
               "an opened file should enter the stable Open working set")
        expect(state.watchedActivity.isEmpty,
               "opening a file should not create a synthetic update")

        try await Task.sleep(nanoseconds: 300_000_000)
        let originalToken = state.renderToken
        try Data("second version from agent".utf8).write(to: opened, options: .atomic)
        for _ in 0..<60 where state.renderToken == originalToken {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        expect(state.renderToken > originalToken,
               "an external replacement should automatically re-render the current file")
        expect(state.markdownText == "second version from agent",
               "auto-refresh should load the replacement contents")
        expect(state.unreadUpdate(for: opened.path) != nil,
               "a changed open document should receive update state in place")
        expect(state.updates(limit: 5).isEmpty,
               "a changed open document should not be duplicated under Updates")

        let newFile = root.appendingPathComponent("new-agent-output.md")
        try Data("new".utf8).write(to: newFile)
        state.refreshProjects()
        for _ in 0..<40 where !state.watchedActivity.contains(where: {
            $0.path == newFile.path
        }) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        expect(state.watchedActivity.contains(where: { $0.path == newFile.path }),
               "new project Markdown should appear in the global Watched feed")
        expect(!state.projectFiles(in: project).contains(where: { $0.path == newFile.path }),
               "new files should not appear under a project until opened")

        print("AppStateIntegrationTests passed")
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
