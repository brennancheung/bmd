import Darwin
import Foundation

@main
enum EditorStateTests {
    static func main() {
        testCleanExternalRefresh()
        testDirtyExternalConflict()
        testSaveAndReloadTransitions()
        testBuffersRemainIndependent()
        print("EditorStateTests passed")
    }

    private static func testCleanExternalRefresh() {
        var state = EditorWorkspaceState()
        state.beginEditing(path: "/a.md", diskText: "first")
        let revision = state.revision

        expect(state.observeDiskText(path: "/a.md", text: "agent update") == .refreshed,
               "a clean editor should accept an external update")
        expect(state.text(for: "/a.md", fallback: "") == "agent update",
               "a clean editor should contain the external text")
        expect(state.revision > revision,
               "an accepted external update should request a WebKit refresh")
    }

    private static func testDirtyExternalConflict() {
        var state = EditorWorkspaceState()
        state.beginEditing(path: "/a.md", diskText: "first")
        state.updateBuffer(path: "/a.md", text: "my edit", diskText: "first")
        let revision = state.revision

        expect(state.observeDiskText(path: "/a.md", text: "agent update") == .conflict,
               "an external update must conflict with unsaved edits")
        expect(state.text(for: "/a.md", fallback: "") == "my edit",
               "a conflict must preserve the user's buffer")
        expect(state.buffer(for: "/a.md")?.externalText == "agent update",
               "a conflict should retain the external version")
        expect(state.revision == revision,
               "a conflict must not replace the visible editor text")
    }

    private static func testSaveAndReloadTransitions() {
        var state = EditorWorkspaceState()
        state.beginEditing(path: "/a.md", diskText: "first")
        state.updateBuffer(path: "/a.md", text: "my edit", diskText: "first")
        state.markSaved(path: "/a.md", text: "my edit")
        expect(!state.isDirty(path: "/a.md"), "saving should clear dirty state")
        expect(state.buffer(for: "/a.md")?.hasExternalConflict == false,
               "saving should clear conflict state")

        state.updateBuffer(path: "/a.md", text: "another edit", diskText: "my edit")
        state.reloadFromDisk(path: "/a.md", text: "agent wins")
        expect(state.text(for: "/a.md", fallback: "") == "agent wins",
               "reloading should replace the edit buffer")
        expect(!state.isDirty(path: "/a.md"), "reloading should produce a clean buffer")
    }

    private static func testBuffersRemainIndependent() {
        var state = EditorWorkspaceState()
        state.beginEditing(path: "/a.md", diskText: "a")
        state.updateBuffer(path: "/a.md", text: "edited a", diskText: "a")
        state.showPreview()
        state.beginEditing(path: "/b.md", diskText: "b")

        expect(state.text(for: "/a.md", fallback: "") == "edited a",
               "switching documents should retain an unsaved buffer")
        expect(state.text(for: "/b.md", fallback: "") == "b",
               "each document should have its own buffer")
        expect(state.dirtyPaths == ["/a.md"],
               "dirty tracking should identify only changed documents")
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
