import SwiftUI
import AppKit

@main
struct bmdApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var preferences = AppPreferences()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
        .defaultSize(width: 1680, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    appState.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Clear Recents") {
                    appState.clearRecents()
                }
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
