import AppKit
import Darwin
import Foundation

@main
enum HistoryShortcutTests {
    static func main() {
        expect(resolve("[") == .back, "[ should go Back")
        expect(resolve("]") == .forward, "] should go Forward")
        expect(resolve("[", modifiers: .command) == .back,
               "Command-[ should remain a Back alias")
        expect(resolve("]", modifiers: .command) == .forward,
               "Command-] should remain a Forward alias")
        expect(resolve("[", isEditingText: true) == nil,
               "plain brackets should remain typeable in text fields")
        expect(resolve("[", modifiers: .command, isEditingText: true) == .back,
               "Command aliases should remain active while editing text")
        expect(resolve("[", modifiers: .shift) == nil,
               "unrelated modified brackets should pass through")
        expect(resolve("x") == nil, "unrelated keys should pass through")
        print("HistoryShortcutTests passed")
    }

    private static func resolve(
        _ characters: String,
        modifiers: NSEvent.ModifierFlags = [],
        isEditingText: Bool = false
    ) -> HistoryShortcutAction? {
        HistoryShortcutResolver.action(
            for: characters,
            modifiers: modifiers,
            isEditingText: isEditingText
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
