import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView()
        }
        .navigationTitle(appState.currentTitle)
        .background {
            MainWindowPlacementView(widthPreset: preferences.windowWidthPreset)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("Appearance", selection: $preferences.appearance) {
                        ForEach(AppearancePreference.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }
                .help("Appearance")

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings")
            }
        }
        .onAppear {
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.appState = appState
                delegate.drainPending(into: appState)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    if url.hasDirectoryPath {
                        appState.addFolder(url)
                    } else {
                        appState.openFile(url)
                    }
                }
            }
            handled = true
        }
        return handled
    }
}

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            Section("Recents") {
                if appState.recents.isEmpty {
                    Text("No recent files")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.recents) { item in
                        Button {
                            appState.openRecent(item)
                        } label: {
                            Label(item.displayName, systemImage: "doc.richtext")
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remove from Recents", role: .destructive) {
                                appState.removeRecent(item)
                            }
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            }
                        }
                    }
                }
            }

            Section {
                if appState.pins.isEmpty {
                    Button("Add a folder…") {
                        appState.presentAddFolderPanel()
                    }
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.pins) { pin in
                        FolderSidebarRow(folder: pin)
                    }
                }
            } header: {
                HStack {
                    Text("Folders")
                    Spacer()
                    Button {
                        appState.presentAddFolderPanel()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("Add Folder")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    appState.presentOpenPanel()
                } label: {
                    Label("Open", systemImage: "folder")
                }
                Button {
                    appState.presentAddFolderPanel()
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
            }
            .buttonStyle(.borderless)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
        .frame(minWidth: 220)
    }
}

private struct FolderSidebarRow: View {
    @EnvironmentObject private var appState: AppState
    @State private var isExpanded = true
    let folder: BookmarkItem

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            let activity = appState.folderActivity(in: folder)
            let files = appState.watchedFiles(in: folder)

            if !activity.isEmpty {
                Label("New & Updated", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(activity) { file in
                    fileButton(file, isActivity: true)
                }
                Divider()
            }

            if files.isEmpty {
                Text("No Markdown files")
                    .foregroundStyle(.secondary)
            } else {
                if !activity.isEmpty {
                    Text("All Markdown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(files) { file in
                    fileButton(file, isActivity: false)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Label(folder.displayName, systemImage: "folder")
                    .lineLimit(1)
                Spacer(minLength: 4)
                let activityCount = appState.folderActivity(in: folder).count
                if activityCount > 0 {
                    Text("\(activityCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
        .contextMenu {
            Button("Refresh") {
                appState.refreshFolders()
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([folder.url])
            }
            Divider()
            Button("Remove Folder", role: .destructive) {
                appState.removeFolder(folder)
            }
        }
    }

    private func fileButton(
        _ file: WatchedMarkdownFile,
        isActivity: Bool
    ) -> some View {
        Button {
            appState.openFile(file.url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isActivity ? "circle.fill" : "doc.richtext")
                    .font(isActivity ? Font.system(size: 6) : Font.body)
                    .foregroundStyle(isActivity ? Color.accentColor : Color.secondary)
                Text(file.relativePath)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .buttonStyle(.plain)
        .help(file.path)
    }
}

struct DetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        VStack(spacing: 0) {
            if let status = appState.statusMessage {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.red.opacity(0.08))
            }

            MarkdownWebView(
                markdown: appState.markdownText,
                title: appState.currentTitle,
                baseDirectory: appState.baseDirectory,
                renderToken: appState.renderToken,
                zoomScale: preferences.zoomScale,
                proseWidth: preferences.proseWidth,
                tableWidth: preferences.tableWidth
            )
            .frame(
                minWidth: 320,
                maxWidth: .infinity,
                minHeight: 320,
                maxHeight: .infinity
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
