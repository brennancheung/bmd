import SwiftUI
import AppKit

@main
struct bmdApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("bmd", id: "main") {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    appDelegate.appState = appState
                    appDelegate.drainPending(into: appState)
                }
        }
        .defaultSize(width: 1100, height: 750)
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
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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
