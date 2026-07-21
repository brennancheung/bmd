import Combine
import Foundation

enum WindowWidthPreset: String, CaseIterable, Identifiable {
    case comfortable
    case wide
    case extraWide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .comfortable: "Comfortable"
        case .wide: "Wide"
        case .extraWide: "Extra Wide"
        }
    }

    var targetWidth: Double {
        switch self {
        case .comfortable: 1360
        case .wide: 1920
        case .extraWide: 2240
        }
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

struct IgnorePatternPreference: Identifiable, Equatable {
    let id: UUID
    var value: String

    init(id: UUID = UUID(), value: String) {
        self.id = id
        self.value = value
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    enum Defaults {
        static let windowWidthPreset = WindowWidthPreset.wide
        static let appearance = AppearancePreference.system
        static let zoomPercent = 125.0
        static let proseWidth = 820.0
        static let tableWidth = 1200.0
        static let sidebarSectionHeaderScalePercent = 140.0
        static let updateFileLimit = 5
        static let ignoredPatterns = ["node_modules"]
        static let usesGitIgnoreFiles = true
        static let usesVimEditorBindings = false
    }

    enum Limits {
        static let zoomPercent = 75.0...200.0
        static let proseWidth = 640.0...1040.0
        static let tableWidth = 820.0...1600.0
        static let sidebarSectionHeaderScalePercent = 75.0...175.0
        static let updateFileLimit = 1...20

        static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
            min(max(value, range.lowerBound), range.upperBound)
        }
    }

    private enum Key {
        static let defaultsVersion = "bmd.preferences.defaultsVersion"
        static let windowWidthPreset = "bmd.preferences.windowWidthPreset"
        static let appearance = "bmd.preferences.appearance"
        static let zoomPercent = "bmd.preferences.zoomPercent"
        static let proseWidth = "bmd.preferences.proseWidth"
        static let tableWidth = "bmd.preferences.tableWidth"
        static let sidebarSectionHeaderScalePercent =
            "bmd.preferences.sidebarSectionHeaderScalePercent"
        static let updateFileLimit = "bmd.preferences.updateFileLimit"
        static let legacyWatchedFileLimit = "bmd.preferences.watchedFileLimit"
        static let ignoredPatterns = "bmd.preferences.ignoredPatterns"
        static let legacyIgnoredDirectoryNamesText =
            "bmd.preferences.ignoredDirectoryNames"
        static let usesGitIgnoreFiles = "bmd.preferences.usesGitIgnoreFiles"
        static let usesVimEditorBindings = "bmd.preferences.usesVimEditorBindings"
    }

    private static let currentDefaultsVersion = 7
    private static let zoomDefaultsVersion = 2
    private static let sidebarHeaderDefaultsVersion = 6
    private let store: UserDefaults

    @Published var windowWidthPreset: WindowWidthPreset {
        didSet { store.set(windowWidthPreset.rawValue, forKey: Key.windowWidthPreset) }
    }

    @Published var appearance: AppearancePreference {
        didSet { store.set(appearance.rawValue, forKey: Key.appearance) }
    }

    @Published var zoomPercent: Double {
        didSet { store.set(zoomPercent, forKey: Key.zoomPercent) }
    }

    @Published var proseWidth: Double {
        didSet { store.set(proseWidth, forKey: Key.proseWidth) }
    }

    @Published var tableWidth: Double {
        didSet { store.set(tableWidth, forKey: Key.tableWidth) }
    }

    @Published var sidebarSectionHeaderScalePercent: Double {
        didSet {
            store.set(
                sidebarSectionHeaderScalePercent,
                forKey: Key.sidebarSectionHeaderScalePercent
            )
        }
    }

    @Published var updateFileLimit: Int {
        didSet { store.set(updateFileLimit, forKey: Key.updateFileLimit) }
    }

    @Published var ignoredPatterns: [IgnorePatternPreference] {
        didSet {
            store.set(ignoredPatterns.map(\.value), forKey: Key.ignoredPatterns)
        }
    }

    @Published var usesGitIgnoreFiles: Bool {
        didSet { store.set(usesGitIgnoreFiles, forKey: Key.usesGitIgnoreFiles) }
    }

    @Published var usesVimEditorBindings: Bool {
        didSet { store.set(usesVimEditorBindings, forKey: Key.usesVimEditorBindings) }
    }

    var zoomScale: Double { zoomPercent / 100 }
    var sidebarSectionHeaderScale: Double { sidebarSectionHeaderScalePercent / 100 }

    var ignoredGlobPatterns: [String] {
        MarkdownScanConfiguration(
            customPatterns: ignoredPatterns.map(\.value),
            usesGitIgnoreFiles: usesGitIgnoreFiles
        ).customPatterns
    }

    var watchConfigurationID: String {
        ([usesGitIgnoreFiles ? "gitignore:on" : "gitignore:off"] + ignoredGlobPatterns)
            .joined(separator: "\u{1f}")
    }

    @discardableResult
    func addIgnorePattern() -> UUID {
        let item = IgnorePatternPreference(value: "")
        ignoredPatterns.append(item)
        return item.id
    }

    func removeIgnorePattern(id: UUID) {
        ignoredPatterns.removeAll { $0.id == id }
    }

    func removeEmptyIgnorePatterns() {
        ignoredPatterns.removeAll {
            $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func storedIgnorePatterns(in store: UserDefaults) -> [String] {
        if store.object(forKey: Key.ignoredPatterns) != nil {
            return store.stringArray(forKey: Key.ignoredPatterns) ?? []
        }
        if let legacy = store.string(forKey: Key.legacyIgnoredDirectoryNamesText) {
            return legacy
                .split(whereSeparator: { $0 == "," || $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return Defaults.ignoredPatterns
    }

    private static func storedGitIgnorePreference(in store: UserDefaults) -> Bool {
        guard store.object(forKey: Key.usesGitIgnoreFiles) != nil else {
            return Defaults.usesGitIgnoreFiles
        }
        return store.bool(forKey: Key.usesGitIgnoreFiles)
    }

    private static func ignorePatternPreferences(
        from values: [String]
    ) -> [IgnorePatternPreference] {
        values.map { IgnorePatternPreference(value: $0) }
    }

    init(store: UserDefaults = .standard) {
        self.store = store

        windowWidthPreset = WindowWidthPreset(
            rawValue: store.string(forKey: Key.windowWidthPreset) ?? ""
        ) ?? Defaults.windowWidthPreset
        appearance = AppearancePreference(
            rawValue: store.string(forKey: Key.appearance) ?? ""
        ) ?? Defaults.appearance

        let storedZoom = Self.number(
            in: store,
            forKey: Key.zoomPercent,
            fallback: Defaults.zoomPercent,
            range: Limits.zoomPercent
        )
        let needsZoomMigration = store.integer(forKey: Key.defaultsVersion)
            < Self.zoomDefaultsVersion
            && storedZoom == 115
        zoomPercent = needsZoomMigration ? Defaults.zoomPercent : storedZoom

        proseWidth = Self.number(
            in: store,
            forKey: Key.proseWidth,
            fallback: Defaults.proseWidth,
            range: Limits.proseWidth
        )
        tableWidth = Self.number(
            in: store,
            forKey: Key.tableWidth,
            fallback: Defaults.tableWidth,
            range: Limits.tableWidth
        )
        let storedSidebarHeaderScale = Self.number(
            in: store,
            forKey: Key.sidebarSectionHeaderScalePercent,
            fallback: Defaults.sidebarSectionHeaderScalePercent,
            range: Limits.sidebarSectionHeaderScalePercent
        )
        let needsSidebarHeaderMigration = store.integer(forKey: Key.defaultsVersion)
            < Self.sidebarHeaderDefaultsVersion
            && (storedSidebarHeaderScale == 100 || storedSidebarHeaderScale == 125)
        sidebarSectionHeaderScalePercent = needsSidebarHeaderMigration
            ? Defaults.sidebarSectionHeaderScalePercent
            : storedSidebarHeaderScale
        let updateFileLimitKey = store.object(forKey: Key.updateFileLimit) == nil
            ? Key.legacyWatchedFileLimit
            : Key.updateFileLimit
        updateFileLimit = Self.integer(
            in: store,
            forKey: updateFileLimitKey,
            fallback: Defaults.updateFileLimit,
            range: Limits.updateFileLimit
        )
        ignoredPatterns = Self.ignorePatternPreferences(
            from: Self.storedIgnorePatterns(in: store)
        )
        usesGitIgnoreFiles = Self.storedGitIgnorePreference(in: store)
        usesVimEditorBindings = store.object(forKey: Key.usesVimEditorBindings) == nil
            ? Defaults.usesVimEditorBindings
            : store.bool(forKey: Key.usesVimEditorBindings)

        store.set(zoomPercent, forKey: Key.zoomPercent)
        store.set(updateFileLimit, forKey: Key.updateFileLimit)
        store.set(ignoredPatterns.map(\.value), forKey: Key.ignoredPatterns)
        store.set(usesGitIgnoreFiles, forKey: Key.usesGitIgnoreFiles)
        store.set(usesVimEditorBindings, forKey: Key.usesVimEditorBindings)
        store.set(Self.currentDefaultsVersion, forKey: Key.defaultsVersion)
    }

    func zoomIn() {
        setZoom(zoomPercent + 10)
    }

    func zoomOut() {
        setZoom(zoomPercent - 10)
    }

    func resetZoom() {
        setZoom(100)
    }

    func resetAll() {
        windowWidthPreset = Defaults.windowWidthPreset
        appearance = Defaults.appearance
        zoomPercent = Defaults.zoomPercent
        proseWidth = Defaults.proseWidth
        tableWidth = Defaults.tableWidth
        sidebarSectionHeaderScalePercent = Defaults.sidebarSectionHeaderScalePercent
        updateFileLimit = Defaults.updateFileLimit
        ignoredPatterns = Self.ignorePatternPreferences(from: Defaults.ignoredPatterns)
        usesGitIgnoreFiles = Defaults.usesGitIgnoreFiles
        usesVimEditorBindings = Defaults.usesVimEditorBindings
    }

    private func setZoom(_ value: Double) {
        zoomPercent = Limits.clamp(value, to: Limits.zoomPercent)
    }

    private static func number(
        in store: UserDefaults,
        forKey key: String,
        fallback: Double,
        range: ClosedRange<Double>
    ) -> Double {
        guard let number = store.object(forKey: key) as? NSNumber else {
            return fallback
        }
        return Limits.clamp(number.doubleValue, to: range)
    }

    private static func integer(
        in store: UserDefaults,
        forKey key: String,
        fallback: Int,
        range: ClosedRange<Int>
    ) -> Int {
        guard let number = store.object(forKey: key) as? NSNumber else {
            return fallback
        }
        return min(max(number.intValue, range.lowerBound), range.upperBound)
    }
}
