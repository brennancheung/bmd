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

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    appState.saveCurrentEdit()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!appState.isEditing || !appState.currentEditIsDirty)

                Button("Save and Return to Preview") {
                    appState.saveCurrentEdit(returnToPreview: true)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!appState.isEditing)
            }

            CommandMenu("Document") {
                Button("Edit Markdown") {
                    appState.beginEditingCurrentDocument()
                }
                .keyboardShortcut("e", modifiers: [])
                .disabled(appState.currentFile == nil || appState.isEditing)

                Button("Reload Editor from Disk") {
                    appState.reloadCurrentEditFromDisk()
                }
                .disabled(!appState.isEditing || !appState.currentEditIsDirty)
            }

            CommandMenu("Navigate") {
                Button("Back in Document History") {
                    appState.goBack()
                }
                .disabled(!appState.canGoBack)

                Button("Forward in Document History") {
                    appState.goForward()
                }
                .disabled(!appState.canGoForward)

                Divider()

                Button("Previous Open Document") {
                    appState.selectAdjacentOpenDocument(.previous)
                }
                .keyboardShortcut(.tab, modifiers: .shift)
                .disabled(appState.openDocuments.count < 2 || appState.isEditing)

                Button("Next Open Document") {
                    appState.selectAdjacentOpenDocument(.next)
                }
                .keyboardShortcut(.tab, modifiers: [])
                .disabled(appState.openDocuments.count < 2 || appState.isEditing)

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
                .disabled(appState.isEditing)

                Button(
                    appState.currentProject.map { "Search “\($0.displayName)”…" }
                        ?? "Search Current Project…"
                ) {
                    appState.showCurrentProjectSearch()
                }
                .keyboardShortcut("p", modifiers: .control)
                .disabled(appState.isEditing)
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
        .defaultSize(width: 720, height: 960)
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?
    private var pendingURLs: [URL] = []
    private var historyShortcutMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame main")
        historyShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            self?.handleHistoryShortcut(event) ?? event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let historyShortcutMonitor {
            NSEvent.removeMonitor(historyShortcutMonitor)
            self.historyShortcutMonitor = nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard appState?.hasUnsavedEdits == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Discard unsaved Markdown edits?"
        alert.informativeText = "bmd is holding one or more unsaved edit buffers. Quitting now will discard them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit and Discard Edits")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
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

    private func handleHistoryShortcut(_ event: NSEvent) -> NSEvent? {
        if shouldBeginEditing(for: event) {
            appState?.beginEditingCurrentDocument()
            return nil
        }
        guard appState?.isEditing != true else { return event }
        let action = HistoryShortcutResolver.action(
            for: event.charactersIgnoringModifiers,
            modifiers: event.modifierFlags,
            isEditingText: isEditingText || appState?.isEditing == true
        )
        switch action {
        case .back:
            appState?.goBack()
            return nil
        case .forward:
            appState?.goForward()
            return nil
        case nil:
            return event
        }
    }

    private func shouldBeginEditing(for event: NSEvent) -> Bool {
        guard appState?.currentFile != nil,
              appState?.isEditing != true,
              !isEditingText else {
            return false
        }
        let relevantModifiers = event.modifierFlags.intersection([
            .command, .control, .option, .shift,
        ])
        return relevantModifiers.isEmpty
            && event.charactersIgnoringModifiers?.lowercased() == "e"
    }

    private var isEditingText: Bool {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
            return false
        }
        return textView.isEditable
    }
}
