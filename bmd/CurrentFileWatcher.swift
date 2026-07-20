import CoreServices
import Foundation

struct MarkdownFileSnapshot: Equatable {
    let path: String
    let modifiedAt: Date
    let byteSize: Int

    var url: URL { URL(fileURLWithPath: path) }
}

struct MarkdownFileSnapshotReader {
    func read(_ file: URL) -> MarkdownFileSnapshot? {
        let normalized = file.standardizedFileURL
        guard let values = try? normalized.resourceValues(
            forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        ), values.isRegularFile == true else {
            return nil
        }
        return MarkdownFileSnapshot(
            path: normalized.path,
            modifiedAt: values.contentModificationDate ?? .distantPast,
            byteSize: values.fileSize ?? 0
        )
    }
}

final class CurrentMarkdownFileWatcher {
    var onChange: (@MainActor (MarkdownFileSnapshot) -> Void)?

    private let queue = DispatchQueue(label: "com.brennan.bmd.current-file-watcher")
    private let reader: MarkdownFileSnapshotReader
    private var file: URL?
    private var previousSnapshot: MarkdownFileSnapshot?
    private var stream: FSEventStreamRef?

    init(reader: MarkdownFileSnapshotReader = MarkdownFileSnapshotReader()) {
        self.reader = reader
    }

    deinit {
        stopStream()
    }

    func watch(file: URL) {
        let normalized = file.standardizedFileURL
        queue.async { [weak self] in
            guard let self else { return }
            stopStream()
            self.file = normalized
            previousSnapshot = reader.read(normalized)
            startStream(for: normalized.deletingLastPathComponent())
        }
    }

    private func startStream(for directory: URL) {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<CurrentMarkdownFileWatcher>
                .fromOpaque(info)
                .takeUnretainedValue()
                .publishChangeIfNeeded()
        }
        stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    private func publishChangeIfNeeded() {
        guard let file else { return }
        let currentSnapshot = reader.read(file)
        guard currentSnapshot != previousSnapshot else { return }
        previousSnapshot = currentSnapshot
        guard let currentSnapshot else { return }

        Task { @MainActor [weak self] in
            self?.onChange?(currentSnapshot)
        }
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
