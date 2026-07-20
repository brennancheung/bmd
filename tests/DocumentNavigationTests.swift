import Darwin
import Foundation

@main
enum DocumentNavigationTests {
    static func main() {
        testStableOpenOrdering()
        testPinningAndManualMovement()
        testPositionalAndAdjacentNavigation()
        testCloseReplacement()
        testBackForwardHistory()
        testQuickSwitcherDeduplicationAndSearch()
        testLegacyRecentsMigration()
        print("DocumentNavigationTests passed")
    }

    private static func testStableOpenOrdering() {
        let first = URL(fileURLWithPath: "/tmp/project/first.md")
        let second = URL(fileURLWithPath: "/tmp/project/second.md")
        let third = URL(fileURLWithPath: "/tmp/project/third.md")
        var open: [OpenDocumentItem] = []
        open = DocumentNavigation.rememberOpen(
            first, in: open, at: date(1)
        )
        open = DocumentNavigation.rememberOpen(
            second, in: open, at: date(2)
        )
        open = DocumentNavigation.rememberOpen(
            first, in: open, at: date(3)
        )
        expect(open.map(\.path) == [first.path, second.path],
               "reopening a document must not move its row")

        open = DocumentNavigation.rememberOpen(
            third, in: open, at: date(4)
        )
        expect(open.map(\.path) == [first.path, second.path, third.path],
               "new documents should append without silently evicting stable rows")
    }

    private static func testPinningAndManualMovement() {
        let first = OpenDocumentItem(
            file: URL(fileURLWithPath: "/tmp/first.md"), at: date(1)
        )
        let second = OpenDocumentItem(
            file: URL(fileURLWithPath: "/tmp/second.md"), at: date(2)
        )
        var open = DocumentNavigation.togglePin(path: first.path, in: [first, second])
        expect(open.first?.isPinned == true, "pinning should persist on the same row")
        open = DocumentNavigation.move(path: second.path, by: -1, in: open)
        expect(open.map(\.path) == [second.path, first.path],
               "manual movement should be explicit and deterministic")
    }

    private static func testPositionalAndAdjacentNavigation() {
        let open = (1...10).map { index in
            OpenDocumentItem(
                file: URL(fileURLWithPath: "/tmp/\(index).md"),
                at: date(TimeInterval(index))
            )
        }

        expect(
            DocumentNavigation.document(atShortcutPosition: 1, in: open)?.path
                == "/tmp/1.md",
            "Command-1 should select the first stable Open position"
        )
        expect(
            DocumentNavigation.document(atShortcutPosition: 9, in: open)?.path
                == "/tmp/9.md",
            "Command-9 should select the ninth stable Open position"
        )
        expect(
            DocumentNavigation.document(atShortcutPosition: 10, in: open) == nil,
            "number shortcuts should be limited to positions one through nine"
        )
        expect(
            DocumentNavigation.adjacentDocument(
                to: "/tmp/10.md",
                direction: .next,
                in: open
            )?.path == "/tmp/1.md",
            "Next Open should wrap from the last row to the first"
        )
        expect(
            DocumentNavigation.adjacentDocument(
                to: "/tmp/1.md",
                direction: .previous,
                in: open
            )?.path == "/tmp/10.md",
            "Previous Open should wrap from the first row to the last"
        )
    }

    private static func testCloseReplacement() {
        let open = (1...3).map { index in
            OpenDocumentItem(
                file: URL(fileURLWithPath: "/tmp/\(index).md"),
                at: date(TimeInterval(index))
            )
        }

        expect(
            DocumentNavigation.replacementAfterClosing(
                path: "/tmp/2.md",
                in: open
            )?.path == "/tmp/3.md",
            "closing a middle row should select the next row"
        )
        expect(
            DocumentNavigation.replacementAfterClosing(
                path: "/tmp/3.md",
                in: open
            )?.path == "/tmp/2.md",
            "closing the last row should select the previous row"
        )
    }

    private static func testBackForwardHistory() {
        var history = DocumentHistoryState()
        history.record("/tmp/a.md")
        history.record("/tmp/b.md")
        history.record("/tmp/c.md")
        expect(history.goBack() == "/tmp/b.md", "Back should return the prior document")
        expect(history.goBack() == "/tmp/a.md", "Back should continue through history")
        expect(history.goForward() == "/tmp/b.md", "Forward should restore the next document")
        history.record("/tmp/d.md")
        expect(!history.canGoForward, "a new branch should discard forward history")
        expect(history.entries == ["/tmp/a.md", "/tmp/b.md", "/tmp/d.md"],
               "history should retain the branch that led to the new document")
    }

    private static func testQuickSwitcherDeduplicationAndSearch() {
        let project = BookmarkItem.folder(URL(fileURLWithPath: "/tmp/project"))
        let file = URL(fileURLWithPath: "/tmp/project/docs/guide.md")
        let open = OpenDocumentItem(file: file, at: date(1))
        let update = WatchedActivityItem(
            path: file.path,
            projectPath: project.path,
            relativePath: "docs/guide.md",
            modifiedAt: date(2),
            detectedAt: date(2),
            readAt: nil
        )
        let candidates = DocumentNavigation.candidates(
            openDocuments: [open],
            updates: [update],
            projects: [project],
            projectFilesByFolder: [
                project.path: [BookmarkItem.file(file, at: date(1))],
            ],
            history: DocumentHistoryState(entries: [file.path]),
            currentPath: nil,
            query: "guide docs"
        )
        expect(candidates.count == 1, "the switcher should show one row per document")
        expect(candidates.first?.source == .open,
               "the persistent Open representation should win deduplication")
        expect(candidates.first?.hasUnreadUpdate == true,
               "deduplication should preserve the unread update state")

        let second = OpenDocumentItem(
            file: URL(fileURLWithPath: "/tmp/project/other.md"),
            at: date(3)
        )
        let switching = DocumentNavigation.candidates(
            openDocuments: [open, second],
            updates: [],
            projects: [project],
            projectFilesByFolder: [:],
            history: DocumentHistoryState(),
            currentPath: open.path,
            query: ""
        )
        expect(switching.first?.path == second.path,
               "the switcher should select an alternative before the current document")
    }

    private static func testLegacyRecentsMigration() {
        let suiteName = "bmd-navigation-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fail("could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bmd-navigation-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.md")
        let second = root.appendingPathComponent("second.md")
        _ = FileManager.default.createFile(atPath: first.path, contents: Data())
        _ = FileManager.default.createFile(atPath: second.path, contents: Data())
        let legacy = [
            BookmarkItem.file(first, at: date(1)),
            BookmarkItem.file(second, at: date(2)),
        ]
        defaults.set(try? JSONEncoder().encode(legacy), forKey: "bmd.recents")

        let store = RecentStore(defaults: defaults)
        let migrated = store.loadOpenDocuments()
        expect(migrated.map(\.path) == legacy.map(\.path),
               "legacy recents should seed Open without changing their visible order")

        var pinned = migrated
        pinned[0].isPinned = true
        store.saveOpenDocuments(pinned)
        expect(store.loadOpenDocuments().first?.isPinned == true,
               "Open pin state should persist")
    }

    private static func date(_ interval: TimeInterval) -> Date {
        Date(timeIntervalSince1970: interval)
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

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("Test failed: \(message)\n".utf8))
        Darwin.exit(EXIT_FAILURE)
    }
}
