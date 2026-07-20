import Darwin
import Foundation

@main
enum CurrentFileWatcherTests {
    @MainActor
    static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory
            .appendingPathComponent("bmd-current-file-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let file = root.appendingPathComponent("report.md")
        try Data("first".utf8).write(to: file)

        let watcher = CurrentMarkdownFileWatcher()
        var changes: [MarkdownFileSnapshot] = []
        watcher.onChange = { snapshot in
            changes.append(snapshot)
        }
        watcher.watch(file: file)
        try await Task.sleep(nanoseconds: 250_000_000)

        let replacement = root.appendingPathComponent("replacement.md")
        try Data("second version".utf8).write(to: replacement)
        try manager.removeItem(at: file)
        try manager.moveItem(at: replacement, to: file)

        for _ in 0..<60 where changes.isEmpty {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        expect(changes.last?.path == file.path,
               "replacing the current file should publish its original path")
        expect(changes.last?.byteSize == "second version".utf8.count,
               "the watcher should publish the replacement file's latest contents")

        print("CurrentFileWatcherTests passed")
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
