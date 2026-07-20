import SwiftUI
import AppKit

@main
struct bmdApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var preferences = AppPreferences()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let openDocumentShortcutKeys: [KeyEquivalent] = [
        "1", "2", "3", "4", "5", "6", "7", "8", "9",
    ]

    var body: some Scene {
        Window("bmd", id: "main") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(preferences)
                .preferredColorScheme(preferredColorScheme)
                .onAppear {
                    appDelegate.appState = appState
                    appDelegate.drainPending(into: appState)
                }
        }
        .defaultSize(width: 1920, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    appState.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Close Unpinned Documents") {
                    appState.closeUnpinnedDocuments()
                }
            }

            CommandMenu("Navigate") {
                Button("Back in Document History") {
                    appState.goBack()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!appState.canGoBack)

                Button("Forward in Document History") {
                    appState.goForward()
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!appState.canGoForward)

                Divider()

                Button("Previous Open Document") {
                    appState.selectAdjacentOpenDocument(.previous)
                }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled(appState.openDocuments.count < 2)

                Button("Next Open Document") {
                    appState.selectAdjacentOpenDocument(.next)
                }
                .keyboardShortcut(.tab, modifiers: .control)
                .disabled(appState.openDocuments.count < 2)

                Menu("Open Document") {
                    ForEach(
                        Array(appState.openDocuments.prefix(9).enumerated()),
                        id: \.element.id
                    ) { index, item in
                        Button(item.displayName) {
                            appState.openDocument(atShortcutPosition: index + 1)
                        }
                        .keyboardShortcut(
                            openDocumentShortcutKeys[index],
                            modifiers: .command
                        )
                    }
                }

                Divider()

                Button("Search All Markdown…") {
                    appState.showGlobalSearch()
                }
                .keyboardShortcut("o", modifiers: .control)

                Button(
                    appState.currentProject.map { "Search “\($0.displayName)”…" }
                        ?? "Search Current Project…"
                ) {
                    appState.showCurrentProjectSearch()
                }
                .keyboardShortcut("p", modifiers: .control)
            }

            CommandGroup(after: .toolbar) {
                Divider()
                Button("Zoom In") {
                    preferences.zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    preferences.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    preferences.resetZoom()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(preferences)
                .preferredColorScheme(preferredColorScheme)
        }
        .defaultSize(width: 680, height: 800)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(preferences)
        } label: {
            Label("BMD", systemImage: "doc.richtext")
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch preferences.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame main")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            if let appState {
                for url in urls {
                    appState.openFile(url)
                }
            } else {
                pendingURLs.append(contentsOf: urls)
            }
        }
    }

    @MainActor
    func drainPending(into appState: AppState) {
        let urls = pendingURLs
        pendingURLs.removeAll()
        for url in urls {
            appState.openFile(url)
        }
    }
}
