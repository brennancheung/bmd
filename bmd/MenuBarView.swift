import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var preferences: AppPreferences

    private let fileLimit = 5

    var body: some View {
        Button {
            showMainWindow()
        } label: {
            Label("Open bmd", systemImage: "macwindow")
        }

        Button {
            showMainWindow()
            appState.presentOpenPanel()
        } label: {
            Label("Open Markdown…", systemImage: "doc.badge.plus")
        }

        Button {
            showMainWindow()
            appState.presentAddProjectPanel()
        } label: {
            Label("Add Project…", systemImage: "folder.badge.plus")
        }

        Divider()

        Section("Updates") {
            let updates = appState.updates(
                limit: min(fileLimit, preferences.updateFileLimit)
            )
            if updates.isEmpty {
                Text("No new updates")
            } else {
                ForEach(updates) { item in
                    Button {
                        appState.openUpdate(item)
                        showMainWindow()
                    } label: {
                        Label(item.displayName, systemImage: "sparkles")
                    }
                    .help(item.path)
                }
            }
        }

        Section("Open") {
            let openDocuments = appState.openDocuments.prefix(fileLimit)
            if openDocuments.isEmpty {
                Text("No open documents")
            } else {
                ForEach(openDocuments) { item in
                    Button {
                        appState.openDocument(item)
                        showMainWindow()
                    } label: {
                        Label(
                            item.displayName,
                            systemImage: appState.currentFile?.path == item.path
                                ? "doc.text.fill"
                                : "doc.text"
                        )
                    }
                    .help(item.path)
                }
            }
        }

        Divider()

        Button {
            appState.selectAdjacentOpenDocument(.previous)
            showMainWindow()
        } label: {
            Label("Previous Open Document", systemImage: "chevron.up")
        }
        .disabled(appState.openDocuments.count < 2)

        Button {
            appState.selectAdjacentOpenDocument(.next)
            showMainWindow()
        } label: {
            Label("Next Open Document", systemImage: "chevron.down")
        }
        .disabled(appState.openDocuments.count < 2)

        Button {
            appState.goBack()
            showMainWindow()
        } label: {
            Label("Back in Document History", systemImage: "chevron.left")
        }
        .disabled(!appState.canGoBack)

        Button {
            appState.goForward()
            showMainWindow()
        } label: {
            Label("Forward in Document History", systemImage: "chevron.right")
        }
        .disabled(!appState.canGoForward)

        Button {
            showMainWindow()
            appState.showQuickSwitcher()
        } label: {
            Label("Switch Document…", systemImage: "doc.text.magnifyingglass")
        }

        Divider()

        if !appState.projects.isEmpty {
            Button {
                appState.refreshProjects()
            } label: {
                Label("Refresh Watched Folders", systemImage: "arrow.clockwise")
            }
        }

        SettingsLink {
            Label("Settings…", systemImage: "gearshape")
        }

        Divider()

        Button("Quit bmd") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
