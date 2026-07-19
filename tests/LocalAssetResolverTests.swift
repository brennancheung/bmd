import Darwin
import Foundation

@main
enum LocalAssetResolverTests {
    static func main() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appendingPathComponent("bmd-local-assets-\(UUID().uuidString)", isDirectory: true)
        let documentDirectory = testRoot.appendingPathComponent("document", isDirectory: true)
        let viewerDirectory = testRoot.appendingPathComponent("viewer", isDirectory: true)
        let outsideDirectory = testRoot.appendingPathComponent("outside", isDirectory: true)

        try fileManager.createDirectory(at: documentDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: viewerDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: testRoot) }

        let image = documentDirectory.appendingPathComponent("assets/image.png")
        try fileManager.createDirectory(
            at: image.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("image".utf8).write(to: image)

        let font = viewerDirectory.appendingPathComponent("fonts/font.woff2")
        try fileManager.createDirectory(
            at: font.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("font".utf8).write(to: font)

        let outside = outsideDirectory.appendingPathComponent("private.txt")
        try Data("private".utf8).write(to: outside)
        let escapingLink = documentDirectory.appendingPathComponent("escape")
        try fileManager.createSymbolicLink(at: escapingLink, withDestinationURL: outsideDirectory)

        expect(
            LocalAssetResolver.resolve(
                URL(string: "bmd-local://document/assets/image.png")!,
                documentDirectory: documentDirectory,
                viewerDirectory: viewerDirectory
            ) == image.standardizedFileURL,
            "document assets should resolve inside the document directory"
        )
        expect(
            LocalAssetResolver.resolve(
                URL(string: "bmd-local://viewer/fonts/font.woff2")!,
                documentDirectory: documentDirectory,
                viewerDirectory: viewerDirectory
            ) == font.standardizedFileURL,
            "viewer assets should resolve inside the viewer directory"
        )
        expect(
            LocalAssetResolver.resolve(
                URL(string: "bmd-local://document/escape/private.txt")!,
                documentDirectory: documentDirectory,
                viewerDirectory: viewerDirectory
            ) == nil,
            "symlinks must not escape the document directory"
        )
        expect(
            LocalAssetResolver.resolve(
                URL(string: "bmd-local://document/%2E%2E/outside/private.txt")!,
                documentDirectory: documentDirectory,
                viewerDirectory: viewerDirectory
            ) == nil,
            "parent-directory traversal must be rejected"
        )
        expect(
            LocalAssetResolver.resolve(
                URL(string: "bmd-local://other/assets/image.png")!,
                documentDirectory: documentDirectory,
                viewerDirectory: viewerDirectory
            ) == nil,
            "unknown asset hosts must be rejected"
        )
        expect(
            LocalAssetResolver.resolve(
                URL(string: "bmd-local://document/")!,
                documentDirectory: documentDirectory,
                viewerDirectory: viewerDirectory
            ) == nil,
            "directory roots must not be served as assets"
        )

        print("LocalAssetResolverTests passed")
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
