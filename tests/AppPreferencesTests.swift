import Darwin
import Foundation

@main
enum AppPreferencesTests {
    @MainActor
    static func main() {
        testDefaultsAndPersistence()
        testLegacyZoomMigration()
        testExistingCustomZoomIsPreserved()
        print("AppPreferencesTests passed")
    }

    @MainActor
    private static func testDefaultsAndPersistence() {
        withStore { store in
            store.set("not-a-preset", forKey: "bmd.preferences.windowWidthPreset")
            store.set("not-an-appearance", forKey: "bmd.preferences.appearance")
            store.set(10, forKey: "bmd.preferences.zoomPercent")
            store.set(99, forKey: "bmd.preferences.watchedFileLimit")
            store.set(0, forKey: "bmd.preferences.recentFileLimit")
            store.set("node_modules, Generated\nCACHE", forKey: "bmd.preferences.ignoredDirectoryNames")

            let preferences = AppPreferences(store: store)
            expect(
                preferences.windowWidthPreset == .wide,
                "invalid window presets should fall back to Wide"
            )
            expect(
                preferences.appearance == .system,
                "invalid appearances should fall back to System"
            )
            expect(
                preferences.zoomPercent == AppPreferences.Limits.zoomPercent.lowerBound,
                "persisted zoom should be clamped"
            )
            expect(preferences.watchedFileLimit == 20, "watched count should be clamped")
            expect(preferences.recentFileLimit == 1, "recent count should be clamped")
            expect(
                preferences.ignoredDirectoryNames == ["node_modules", "generated", "cache"],
                "ignore rules should parse comma and newline separated names case-insensitively"
            )

            preferences.resetZoom()
            expect(preferences.zoomPercent == 100, "Actual Size should reset zoom to 100%")
            preferences.zoomIn()
            expect(preferences.zoomPercent == 110, "Zoom In should advance by 10%")
            preferences.zoomOut()
            expect(preferences.zoomPercent == 100, "Zoom Out should decrease by 10%")

            preferences.windowWidthPreset = .extraWide
            preferences.appearance = .dark
            expect(
                store.string(forKey: "bmd.preferences.windowWidthPreset") == "extraWide",
                "the semantic window width should persist"
            )
            expect(
                store.string(forKey: "bmd.preferences.appearance") == "dark",
                "appearance should persist"
            )

            preferences.resetAll()
            expect(preferences.windowWidthPreset == .wide, "reset should restore Wide")
            expect(preferences.appearance == .system, "reset should restore System appearance")
            expect(
                preferences.zoomPercent == AppPreferences.Defaults.zoomPercent,
                "reset should restore the 125% default zoom"
            )
            expect(preferences.watchedFileLimit == 5, "reset should show five watched files")
            expect(preferences.recentFileLimit == 10, "reset should show ten recent files")
            expect(
                preferences.ignoredDirectoryNames == ["node_modules"],
                "reset should ignore node_modules by default"
            )
        }
    }

    @MainActor
    private static func testLegacyZoomMigration() {
        withStore { store in
            store.set(1, forKey: "bmd.preferences.defaultsVersion")
            store.set(115, forKey: "bmd.preferences.zoomPercent")

            let preferences = AppPreferences(store: store)
            expect(
                preferences.zoomPercent == 125,
                "the previous 115% default should migrate to 125%"
            )
            expect(
                store.integer(forKey: "bmd.preferences.defaultsVersion") == 3,
                "the migration version should persist"
            )
        }
    }

    @MainActor
    private static func testExistingCustomZoomIsPreserved() {
        withStore { store in
            store.set(2, forKey: "bmd.preferences.defaultsVersion")
            store.set(115, forKey: "bmd.preferences.zoomPercent")

            let preferences = AppPreferences(store: store)
            expect(
                preferences.zoomPercent == 115,
                "a post-migration custom 115% zoom should remain unchanged"
            )
        }
    }

    @MainActor
    private static func withStore(_ body: (UserDefaults) -> Void) {
        let suiteName = "bmd-preferences-tests-\(UUID().uuidString)"
        guard let store = UserDefaults(suiteName: suiteName) else {
            fail("could not create isolated UserDefaults suite")
        }
        defer { store.removePersistentDomain(forName: suiteName) }
        body(store)
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
