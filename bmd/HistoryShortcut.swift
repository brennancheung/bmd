import AppKit

enum HistoryShortcutAction: Equatable {
    case back
    case forward
}

enum HistoryShortcutResolver {
    static func action(
        for characters: String?,
        modifiers: NSEvent.ModifierFlags,
        isEditingText: Bool
    ) -> HistoryShortcutAction? {
        let relevantModifiers = modifiers.intersection([
            .command, .control, .option, .shift,
        ])
        guard relevantModifiers.isEmpty || relevantModifiers == .command else {
            return nil
        }
        guard !relevantModifiers.isEmpty || !isEditingText else {
            return nil
        }

        switch characters {
        case "[": return .back
        case "]": return .forward
        default: return nil
        }
    }
}
