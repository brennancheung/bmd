import Darwin
import Foundation

@main
enum AppPreferencesTests {
    @MainActor
    static func main() {
        let suiteName = "bmd-preferences-tests-\(UUID().uuidString)"
        guard let store = UserDefaults(suiteName: suiteName) else {
            fail("could not create isolated UserDefaults suite")
        }
        defer { store.removePersistentDomain(forName: suiteName) }

        store.set(99_999, forKey: "bmd.preferences.windowWidth")
        store.set(10, forKey: "bmd.preferences.zoomPercent")
        let preferences = AppPreferences(store: store)

        expect(
            preferences.windowWidth == AppPreferences.Limits.windowWidth.upperBound,
            "persisted window width should be clamped"
        )
        expect(
            preferences.zoomPercent == AppPreferences.Limits.zoomPercent.lowerBound,
            "persisted zoom should be clamped"
        )

        preferences.resetZoom()
        expect(preferences.zoomPercent == 100, "Actual Size should reset zoom to 100%")
        preferences.zoomIn()
        expect(preferences.zoomPercent == 110, "Zoom In should advance by 10%")
        preferences.zoomOut()
        expect(preferences.zoomPercent == 100, "Zoom Out should decrease by 10%")

        preferences.resetAll()
        expect(
            preferences.windowWidth == AppPreferences.Defaults.windowWidth,
            "reset should restore the default window width"
        )
        expect(
            store.double(forKey: "bmd.preferences.zoomPercent")
                == AppPreferences.Defaults.zoomPercent,
            "changes should persist to UserDefaults"
        )

        print("AppPreferencesTests passed")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("Test failed: \(message)\n".utf8))
        Darwin.exit(EXIT_FAILURE)
    }
}
