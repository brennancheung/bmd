import Combine
import Foundation

@MainActor
final class AppPreferences: ObservableObject {
    enum Defaults {
        static let windowWidth = 1320.0
        static let windowHeight = 900.0
        static let zoomPercent = 115.0
        static let proseWidth = 820.0
        static let tableWidth = 1200.0
        static let centerWindow = true
    }

    enum Limits {
        static let windowWidth = 900.0...2200.0
        static let windowHeight = 650.0...1600.0
        static let zoomPercent = 75.0...200.0
        static let proseWidth = 640.0...1040.0
        static let tableWidth = 820.0...1600.0

        static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
            min(max(value, range.lowerBound), range.upperBound)
        }
    }

    private enum Key {
        static let windowWidth = "bmd.preferences.windowWidth"
        static let windowHeight = "bmd.preferences.windowHeight"
        static let zoomPercent = "bmd.preferences.zoomPercent"
        static let proseWidth = "bmd.preferences.proseWidth"
        static let tableWidth = "bmd.preferences.tableWidth"
        static let centerWindow = "bmd.preferences.centerWindow"
    }

    private let store: UserDefaults

    @Published var windowWidth: Double {
        didSet { store.set(windowWidth, forKey: Key.windowWidth) }
    }

    @Published var windowHeight: Double {
        didSet { store.set(windowHeight, forKey: Key.windowHeight) }
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

    @Published var centerWindow: Bool {
        didSet { store.set(centerWindow, forKey: Key.centerWindow) }
    }

    var zoomScale: Double { zoomPercent / 100 }

    init(store: UserDefaults = .standard) {
        self.store = store
        windowWidth = Self.number(
            in: store,
            forKey: Key.windowWidth,
            fallback: Defaults.windowWidth,
            range: Limits.windowWidth
        )
        windowHeight = Self.number(
            in: store,
            forKey: Key.windowHeight,
            fallback: Defaults.windowHeight,
            range: Limits.windowHeight
        )
        zoomPercent = Self.number(
            in: store,
            forKey: Key.zoomPercent,
            fallback: Defaults.zoomPercent,
            range: Limits.zoomPercent
        )
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
        centerWindow = store.object(forKey: Key.centerWindow) == nil
            ? Defaults.centerWindow
            : store.bool(forKey: Key.centerWindow)
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
        windowWidth = Defaults.windowWidth
        windowHeight = Defaults.windowHeight
        zoomPercent = Defaults.zoomPercent
        proseWidth = Defaults.proseWidth
        tableWidth = Defaults.tableWidth
        centerWindow = Defaults.centerWindow
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
}
