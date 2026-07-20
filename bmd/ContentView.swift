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
                    ForEach(AppearancePreference.allCases) { appearance in
                        Button {
                            preferences.appearance = appearance
                        } label: {
                            if preferences.appearance == appearance {
                                Label(appearance.title, systemImage: "checkmark")
                            } else {
                                Text(appearance.title)
                            }
                        }
                    }
                } label: {
                    Label("Theme", systemImage: "circle.lefthalf.filled")
                }
                .help("Theme")

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
            appState.updateWatchConfiguration(
                ignoredDirectoryNames: preferences.ignoredDirectoryNames
            )
        }
        .task(id: preferences.ignoredDirectoryNamesText) {
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }
            appState.updateWatchConfiguration(
                ignoredDirectoryNames: preferences.ignoredDirectoryNames
            )
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
                        appState.addProject(url)
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
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        List {
            Section {
                let visibleActivity = appState.watchedFiles(
                    limit: preferences.watchedFileLimit
                )
                if visibleActivity.isEmpty {
                    Text("No watched activity")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleActivity) { item in
                        watchedFileButton(item)
                    }
                }
            } header: {
                sectionHeader("Watched")
            }

            Section {
                let visibleRecents = appState.recents.prefix(preferences.recentFileLimit)
                if visibleRecents.isEmpty {
                    Text("No recent files")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleRecents) { item in
                        recentFileButton(item)
                    }
                }
            } header: {
                sectionHeader("Recents")
            }

            Section {
                if appState.projects.isEmpty {
                    Button("Add a project…") {
                        appState.presentAddProjectPanel()
                    }
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.projects) { project in
                        ProjectSidebarRow(project: project)
                    }
                }
            } header: {
                HStack {
                    sectionHeader("Projects")
                    Spacer()
                    Button {
                        appState.presentAddProjectPanel()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Add Project")
                }
            }
        }
        .listStyle(.sidebar)
        .contentMargins(.top, 8, for: .scrollContent)
        .contentMargins(.trailing, 8, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    appState.presentOpenPanel()
                } label: {
                    Label("Open", systemImage: "folder")
                }
                Button {
                    appState.presentAddProjectPanel()
                } label: {
                    Label("Add Project", systemImage: "folder.badge.plus")
                }
            }
            .buttonStyle(.borderless)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
        .frame(minWidth: 240)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(
                .system(
                    size: NSFont.systemFontSize * preferences.sidebarSectionHeaderScale,
                    weight: .semibold
                )
            )
            .foregroundStyle(.secondary)
            .textCase(nil)
    }

    private func watchedFileButton(_ item: WatchedActivityItem) -> some View {
        let isCurrent = appState.currentFile?.path == item.path
        return Button {
            appState.openWatched(item)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isCurrent ? "doc.text.fill" : "doc.text")
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayName)
                        .lineLimit(1)
                    Text(item.contextLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .buttonStyle(.plain)
        .help(item.path)
        .contextMenu {
            Button("Copy Path") {
                copyPath(item.url)
            }
            Button("Reveal in Finder") {
                revealInFinder(item.url)
            }
        }
    }

    private func recentFileButton(_ item: BookmarkItem) -> some View {
        Button {
            appState.openRecent(item)
        } label: {
            Label(appState.recentDisplayPath(item), systemImage: "clock")
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .buttonStyle(.plain)
        .help(item.path)
        .contextMenu {
            Button("Copy Path") {
                copyPath(item.url)
            }
            Button("Reveal in Finder") {
                revealInFinder(item.url)
            }
            Divider()
            Button("Remove from Recents", role: .destructive) {
                appState.removeRecent(item)
            }
        }
    }
}

private struct ProjectSidebarRow: View {
    @EnvironmentObject private var appState: AppState
    @State private var isExpanded = true
    let project: BookmarkItem

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            let files = appState.projectFiles(in: project)
            if files.isEmpty {
                Text("No opened files")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(files) { file in
                    Button {
                        appState.openRecent(file)
                    } label: {
                        Label(
                            MarkdownFolderDiscovery.relativePath(
                                for: file.url,
                                in: project.url
                            ),
                            systemImage: "doc.richtext"
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                    .help(file.path)
                    .contextMenu {
                        Button("Copy Path") {
                            copyPath(file.url)
                        }
                        Button("Reveal in Finder") {
                            revealInFinder(file.url)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Button {
                    isExpanded.toggle()
                } label: {
                    Label(project.displayName, systemImage: "folder")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                let fileCount = appState.projectFiles(in: project).count
                if fileCount > 0 {
                    Text("\(fileCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Button {
                    appState.presentProjectMarkdownPanel(project)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Open Markdown in \(project.displayName)")

                Button {
                    revealInFinder(project.url)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Reveal \(project.displayName) in Finder")
            }
        }
        .contextMenu {
            Button("Copy Path") {
                copyPath(project.url)
            }
            Button("Refresh Watcher") {
                appState.refreshProjects()
            }
            Button("Reveal in Finder") {
                revealInFinder(project.url)
            }
            Divider()
            Button("Remove Project", role: .destructive) {
                appState.removeProject(project)
            }
        }
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

private func copyPath(_ url: URL) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.standardizedFileURL.path, forType: .string)
}

private func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}
