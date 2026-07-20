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

        Section("Watched") {
            let watchedFiles = appState.watchedFiles(
                limit: min(fileLimit, preferences.watchedFileLimit)
            )
            if watchedFiles.isEmpty {
                Text("No watched files")
            } else {
                ForEach(watchedFiles) { item in
                    Button {
                        appState.openWatched(item)
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

        Section("Recently Opened") {
            let recentFiles = appState.recents.prefix(
                min(fileLimit, preferences.recentFileLimit)
            )
            if recentFiles.isEmpty {
                Text("No recent files")
            } else {
                ForEach(recentFiles) { item in
                    Button {
                        appState.openRecent(item)
                        showMainWindow()
                    } label: {
                        Label(appState.recentDisplayPath(item), systemImage: "clock")
                    }
                    .help(item.path)
                }
            }
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
