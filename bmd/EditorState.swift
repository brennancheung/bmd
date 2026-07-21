import Foundation

enum DocumentPresentationMode: Equatable {
    case preview
    case editing
}

enum EditorDiskUpdate: Equatable {
    case untracked
    case unchanged
    case refreshed
    case conflict
}

struct EditorBuffer: Equatable {
    var text: String
    var savedText: String
    var externalText: String?

    var isDirty: Bool { text != savedText }
    var hasExternalConflict: Bool { externalText != nil }
}

/// Pure state for transient edit buffers. File reads and writes remain in AppState.
struct EditorWorkspaceState: Equatable {
    private(set) var mode: DocumentPresentationMode = .preview
    private(set) var revision: UInt64 = 0
    private(set) var buffersByPath: [String: EditorBuffer] = [:]

    var dirtyPaths: Set<String> {
        Set(buffersByPath.compactMap { path, buffer in
            buffer.isDirty ? path : nil
        })
    }

    mutating func beginEditing(path: String, diskText: String) {
        _ = observeDiskText(path: path, text: diskText)
        if buffersByPath[path] == nil {
            buffersByPath[path] = EditorBuffer(
                text: diskText,
                savedText: diskText,
                externalText: nil
            )
        }
        mode = .editing
        revision &+= 1
    }

    mutating func showPreview() {
        mode = .preview
    }

    mutating func updateBuffer(path: String, text: String, diskText: String) {
        var buffer = buffersByPath[path] ?? EditorBuffer(
            text: diskText,
            savedText: diskText,
            externalText: nil
        )
        buffer.text = text
        buffersByPath[path] = buffer
    }

    @discardableResult
    mutating func observeDiskText(path: String, text: String) -> EditorDiskUpdate {
        guard var buffer = buffersByPath[path] else { return .untracked }
        guard text != buffer.savedText else { return .unchanged }

        if buffer.isDirty {
            buffer.externalText = text
            buffersByPath[path] = buffer
            return .conflict
        }

        buffer.text = text
        buffer.savedText = text
        buffer.externalText = nil
        buffersByPath[path] = buffer
        revision &+= 1
        return .refreshed
    }

    mutating func markSaved(path: String, text: String) {
        buffersByPath[path] = EditorBuffer(
            text: text,
            savedText: text,
            externalText: nil
        )
    }

    mutating func reloadFromDisk(path: String, text: String) {
        buffersByPath[path] = EditorBuffer(
            text: text,
            savedText: text,
            externalText: nil
        )
        revision &+= 1
    }

    func buffer(for path: String) -> EditorBuffer? {
        buffersByPath[path]
    }

    func text(for path: String, fallback: String) -> String {
        buffersByPath[path]?.text ?? fallback
    }

    func isDirty(path: String) -> Bool {
        buffersByPath[path]?.isDirty == true
    }
}
