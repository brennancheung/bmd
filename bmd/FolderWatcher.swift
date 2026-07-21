import CoreServices
import Foundation

struct WatchedMarkdownFile: Identifiable, Hashable {
    let rootPath: String
    let path: String
    let relativePath: String
    let modifiedAt: Date
    let byteSize: Int

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var displayName: String { url.lastPathComponent }
}

struct WatchedFolderUpdate {
    let rootPath: String
    let files: [WatchedMarkdownFile]
    let changedFiles: [WatchedMarkdownFile]
    let isInitial: Bool
}

enum MarkdownFolderDiscovery {
    static let supportedExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mdwn",
    ]

    static func changedFiles(
        previous: [WatchedMarkdownFile],
        current: [WatchedMarkdownFile]
    ) -> [WatchedMarkdownFile] {
        let previousByPath = Dictionary(uniqueKeysWithValues: previous.map { ($0.path, $0) })
        return current
            .filter { file in
                guard let old = previousByPath[file.path] else { return true }
                return old.modifiedAt != file.modifiedAt || old.byteSize != file.byteSize
            }
            .sorted { left, right in
                if left.modifiedAt != right.modifiedAt {
                    return left.modifiedAt > right.modifiedAt
                }
                return left.relativePath.localizedCaseInsensitiveCompare(right.relativePath)
                    == .orderedAscending
            }
    }

    static func relativePath(for file: URL, in root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return file.lastPathComponent
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }
}

struct MarkdownFolderScanner {
    var fileManager = FileManager.default

    func scan(
        _ root: URL,
        configuration: MarkdownScanConfiguration = .default
    ) -> [WatchedMarkdownFile] {
        let normalizedRoot = root.standardizedFileURL
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey,
            .fileSizeKey,
        ]
        var files: [WatchedMarkdownFile] = []
        scanDirectory(
            normalizedRoot,
            relativeDirectory: "",
            root: normalizedRoot,
            keys: keys,
            configuration: configuration,
            rules: PathIgnoreRules(configuration: configuration),
            files: &files
        )

        return files.sorted {
            $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath)
                == .orderedAscending
        }
    }

    private func scanDirectory(
        _ directory: URL,
        relativeDirectory: String,
        root: URL,
        keys: [URLResourceKey],
        configuration: MarkdownScanConfiguration,
        rules inheritedRules: PathIgnoreRules,
        files: inout [WatchedMarkdownFile]
    ) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            return
        }

        var rules = inheritedRules
        if configuration.usesGitIgnoreFiles,
           let gitIgnore = entries.first(where: { $0.lastPathComponent == ".gitignore" }),
           let contents = try? String(contentsOf: gitIgnore, encoding: .utf8) {
            rules = rules.addingGitIgnore(contents, in: relativeDirectory)
        }

        for fileURL in entries {
            let name = fileURL.lastPathComponent
            guard !name.hasPrefix(".") else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else {
                continue
            }
            guard values.isSymbolicLink != true else { continue }

            let relativePath = relativeDirectory.isEmpty
                ? name
                : relativeDirectory + "/" + name
            let isDirectory = values.isDirectory == true
            guard !rules.ignores(relativePath, isDirectory: isDirectory) else {
                continue
            }

            if isDirectory {
                guard values.isPackage != true else { continue }
                scanDirectory(
                    fileURL,
                    relativeDirectory: relativePath,
                    root: root,
                    keys: keys,
                    configuration: configuration,
                    rules: rules,
                    files: &files
                )
                continue
            }

            guard values.isRegularFile == true,
                  MarkdownFolderDiscovery.supportedExtensions.contains(
                    fileURL.pathExtension.lowercased()
                  ) else {
                continue
            }

            files.append(
                WatchedMarkdownFile(
                    rootPath: root.path,
                    path: fileURL.standardizedFileURL.path,
                    relativePath: relativePath,
                    modifiedAt: values.contentModificationDate ?? .distantPast,
                    byteSize: values.fileSize ?? 0
                )
            )
        }
    }
}

final class MarkdownFolderWatcher {
    var onUpdate: (@MainActor (WatchedFolderUpdate) -> Void)?

    private let queue = DispatchQueue(label: "com.brennan.bmd.folder-watcher")
    private let scanner: MarkdownFolderScanner
    private var roots: [URL] = []
    private var configuration = MarkdownScanConfiguration.default
    private var previousFilesByRoot: [String: [WatchedMarkdownFile]] = [:]
    private var stream: FSEventStreamRef?

    init(scanner: MarkdownFolderScanner = MarkdownFolderScanner()) {
        self.scanner = scanner
    }

    deinit {
        stopStream()
    }

    func watch(
        folders: [URL],
        configuration: MarkdownScanConfiguration = .default
    ) {
        let normalizedFolders = Array(
            Dictionary(
                folders.map { ($0.standardizedFileURL.path, $0.standardizedFileURL) },
                uniquingKeysWith: { first, _ in first }
            ).values
        ).sorted { $0.path < $1.path }

        queue.async { [weak self] in
            guard let self else { return }
            stopStream()
            roots = normalizedFolders
            self.configuration = configuration
            previousFilesByRoot = [:]

            for root in roots {
                let files = scanner.scan(root, configuration: configuration)
                previousFilesByRoot[root.path] = files
                publish(
                    WatchedFolderUpdate(
                        rootPath: root.path,
                        files: files,
                        changedFiles: [],
                        isInitial: true
                    )
                )
            }
            startStream()
        }
    }

    func refresh() {
        queue.async { [weak self] in
            self?.scanAndPublishChanges()
        }
    }

    private func startStream() {
        guard !roots.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<MarkdownFolderWatcher>
                .fromOpaque(info)
                .takeUnretainedValue()
            watcher.scanAndPublishChanges()
        }

        stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            roots.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.35,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func scanAndPublishChanges() {
        for root in roots {
            let currentFiles = scanner.scan(root, configuration: configuration)
            let previousFiles = previousFilesByRoot[root.path] ?? []
            let changedFiles = MarkdownFolderDiscovery.changedFiles(
                previous: previousFiles,
                current: currentFiles
            )
            previousFilesByRoot[root.path] = currentFiles
            publish(
                WatchedFolderUpdate(
                    rootPath: root.path,
                    files: currentFiles,
                    changedFiles: changedFiles,
                    isInitial: false
                )
            )
        }
    }

    private func publish(_ update: WatchedFolderUpdate) {
        Task { @MainActor [weak self] in
            self?.onUpdate?(update)
        }
    }
}
