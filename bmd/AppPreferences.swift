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

@MainActor
final class AppPreferences: ObservableObject {
    enum Defaults {
        static let windowWidthPreset = WindowWidthPreset.wide
        static let appearance = AppearancePreference.system
        static let zoomPercent = 125.0
        static let proseWidth = 820.0
        static let tableWidth = 1200.0
        static let watchedFileLimit = 5
        static let recentFileLimit = 10
        static let ignoredDirectoryNamesText = "node_modules"
    }

    enum Limits {
        static let zoomPercent = 75.0...200.0
        static let proseWidth = 640.0...1040.0
        static let tableWidth = 820.0...1600.0
        static let watchedFileLimit = 1...20
        static let recentFileLimit = 1...50

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
        static let watchedFileLimit = "bmd.preferences.watchedFileLimit"
        static let recentFileLimit = "bmd.preferences.recentFileLimit"
        static let ignoredDirectoryNamesText = "bmd.preferences.ignoredDirectoryNames"
    }

    private static let currentDefaultsVersion = 3
    private static let zoomDefaultsVersion = 2
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

    @Published var watchedFileLimit: Int {
        didSet { store.set(watchedFileLimit, forKey: Key.watchedFileLimit) }
    }

    @Published var recentFileLimit: Int {
        didSet { store.set(recentFileLimit, forKey: Key.recentFileLimit) }
    }

    @Published var ignoredDirectoryNamesText: String {
        didSet { store.set(ignoredDirectoryNamesText, forKey: Key.ignoredDirectoryNamesText) }
    }

    var zoomScale: Double { zoomPercent / 100 }

    var ignoredDirectoryNames: Set<String> {
        Set(
            ignoredDirectoryNamesText
                .split(whereSeparator: { $0 == "," || $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
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
        watchedFileLimit = Self.integer(
            in: store,
            forKey: Key.watchedFileLimit,
            fallback: Defaults.watchedFileLimit,
            range: Limits.watchedFileLimit
        )
        recentFileLimit = Self.integer(
            in: store,
            forKey: Key.recentFileLimit,
            fallback: Defaults.recentFileLimit,
            range: Limits.recentFileLimit
        )
        ignoredDirectoryNamesText = store.string(forKey: Key.ignoredDirectoryNamesText)
            ?? Defaults.ignoredDirectoryNamesText

        store.set(zoomPercent, forKey: Key.zoomPercent)
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
        watchedFileLimit = Defaults.watchedFileLimit
        recentFileLimit = Defaults.recentFileLimit
        ignoredDirectoryNamesText = Defaults.ignoredDirectoryNamesText
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
