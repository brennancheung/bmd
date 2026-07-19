import AppKit
import Foundation
import UniformTypeIdentifiers

@main
enum SetDefaultMarkdownApp {
    static func main() async {
        let appPath = CommandLine.arguments.dropFirst().first ?? "/Applications/bmd.app"
        let appURL = URL(fileURLWithPath: appPath, isDirectory: true).standardizedFileURL

        guard FileManager.default.fileExists(atPath: appURL.path) else {
            fail("bmd app not found: \(appURL.path)")
        }

        let extensions = ["md", "markdown", "mdown", "mkd", "mdwn"]
        let contentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        var seenIdentifiers = Set<String>()

        do {
            for contentType in contentTypes where seenIdentifiers.insert(contentType.identifier).inserted {
                try await NSWorkspace.shared.setDefaultApplication(
                    at: appURL,
                    toOpen: contentType
                )
                print("Registered \(contentType.identifier) → bmd")
            }
        } catch {
            fail("macOS did not change the default Markdown app: \(error.localizedDescription)")
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(EXIT_FAILURE)
    }
}
