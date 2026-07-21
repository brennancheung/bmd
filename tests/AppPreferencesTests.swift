import Darwin
import Foundation

@main
enum AppPreferencesTests {
    @MainActor
    static func main() {
        testDefaultsAndPersistence()
        testLegacyZoomMigration()
        testExistingCustomZoomIsPreserved()
        testSidebarHeaderMigration()
        print("AppPreferencesTests passed")
    }

    @MainActor
    private static func testDefaultsAndPersistence() {
        withStore { store in
            store.set("not-a-preset", forKey: "bmd.preferences.windowWidthPreset")
            store.set("not-an-appearance", forKey: "bmd.preferences.appearance")
            store.set(10, forKey: "bmd.preferences.zoomPercent")
            store.set(500, forKey: "bmd.preferences.sidebarSectionHeaderScalePercent")
            store.set(99, forKey: "bmd.preferences.watchedFileLimit")
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
            expect(
                preferences.sidebarSectionHeaderScalePercent
                    == AppPreferences.Limits.sidebarSectionHeaderScalePercent.upperBound,
                "persisted section label scaling should be clamped"
            )
            expect(preferences.updateFileLimit == 20, "update count should be clamped")
            expect(
                preferences.ignoredGlobPatterns == ["node_modules", "Generated", "CACHE"],
                "legacy ignore names should migrate into individual list entries"
            )
            expect(preferences.usesGitIgnoreFiles,
                   "project .gitignore rules should be enabled by default")
            expect(!preferences.usesVimEditorBindings,
                   "Vim editor bindings should be opt-in")

            preferences.resetZoom()
            expect(preferences.zoomPercent == 100, "Actual Size should reset zoom to 100%")
            preferences.zoomIn()
            expect(preferences.zoomPercent == 110, "Zoom In should advance by 10%")
            preferences.zoomOut()
            expect(preferences.zoomPercent == 100, "Zoom Out should decrease by 10%")

            preferences.windowWidthPreset = .extraWide
            preferences.appearance = .dark
            preferences.sidebarSectionHeaderScalePercent = 135
            preferences.ignoredPatterns.append(
                IgnorePatternPreference(value: "build/**")
            )
            preferences.usesGitIgnoreFiles = false
            preferences.usesVimEditorBindings = true
            expect(
                store.string(forKey: "bmd.preferences.windowWidthPreset") == "extraWide",
                "the semantic window width should persist"
            )
            expect(
                store.string(forKey: "bmd.preferences.appearance") == "dark",
                "appearance should persist"
            )
            expect(
                store.double(forKey: "bmd.preferences.sidebarSectionHeaderScalePercent") == 135,
                "section label scaling should persist"
            )
            expect(
                store.stringArray(forKey: "bmd.preferences.ignoredPatterns")
                    == ["node_modules", "Generated", "CACHE", "build/**"],
                "ignore patterns should persist as a native list"
            )
            expect(
                store.bool(forKey: "bmd.preferences.usesGitIgnoreFiles") == false,
                "the .gitignore preference should persist"
            )
            expect(store.bool(forKey: "bmd.preferences.usesVimEditorBindings"),
                   "the Vim editor preference should persist")
            let reloaded = AppPreferences(store: store)
            expect(
                reloaded.ignoredGlobPatterns
                    == ["node_modules", "Generated", "CACHE", "build/**"],
                "ignore-pattern rows should survive a preferences reload"
            )
            expect(!reloaded.usesGitIgnoreFiles,
                   "the disabled .gitignore option should survive a preferences reload")
            expect(reloaded.usesVimEditorBindings,
                   "Vim bindings should survive a preferences reload")

            preferences.resetAll()
            expect(preferences.windowWidthPreset == .wide, "reset should restore Wide")
            expect(preferences.appearance == .system, "reset should restore System appearance")
            expect(
                preferences.zoomPercent == AppPreferences.Defaults.zoomPercent,
                "reset should restore the 125% default zoom"
            )
            expect(
                preferences.sidebarSectionHeaderScalePercent == 140,
                "reset should restore the default section label scaling"
            )
            expect(preferences.updateFileLimit == 5, "reset should show five updates")
            expect(
                preferences.ignoredGlobPatterns == ["node_modules"],
                "reset should ignore node_modules by default"
            )
            expect(preferences.usesGitIgnoreFiles,
                   "reset should restore project .gitignore support")
            expect(!preferences.usesVimEditorBindings,
                   "reset should disable Vim editor bindings")
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
                store.integer(forKey: "bmd.preferences.defaultsVersion") == 7,
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
    private static func testSidebarHeaderMigration() {
        withStore { store in
            store.set(5, forKey: "bmd.preferences.defaultsVersion")
            store.set(125, forKey: "bmd.preferences.sidebarSectionHeaderScalePercent")

            let preferences = AppPreferences(store: store)
            expect(
                preferences.sidebarSectionHeaderScalePercent == 140,
                "the previous 125% section label default should migrate to 140%"
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
