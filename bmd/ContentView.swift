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
                Button {
                    appState.goBack()
                } label: {
                    Label("Back in Document History", systemImage: "chevron.left")
                }
                .disabled(!appState.canGoBack)
                .help("Back in Document History (⌘[)")

                Button {
                    appState.goForward()
                } label: {
                    Label("Forward in Document History", systemImage: "chevron.right")
                }
                .disabled(!appState.canGoForward)
                .help("Forward in Document History (⌘])")

                Button {
                    appState.showGlobalSearch()
                } label: {
                    Label("Search All Markdown", systemImage: "doc.text.magnifyingglass")
                }
                .help("Search All Markdown (⌃O)")

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
        .sheet(isPresented: $appState.isQuickSwitcherPresented) {
            QuickSwitcherView()
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 520)
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
    @StateObject private var modifierKeys = ModifierKeyObserver()

    var body: some View {
        List {
            Section {
                let visibleUpdates = appState.updates(
                    limit: preferences.updateFileLimit
                )
                if visibleUpdates.isEmpty {
                    Text("No new updates")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleUpdates) { item in
                        updateFileButton(item)
                    }
                }
            } header: {
                sectionHeader("Updates")
            }

            Section {
                if appState.openDocuments.isEmpty {
                    Text("No open documents")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(
                        Array(appState.openDocuments.enumerated()),
                        id: \.element.id
                    ) { index, item in
                        openDocumentButton(item, position: index + 1)
                    }
                }
            } header: {
                sectionHeader("Open")
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
        .padding(.top, 8)
        .padding(.trailing, 8)
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
        .onAppear {
            modifierKeys.start()
        }
        .onDisappear {
            modifierKeys.stop()
        }
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

    private func updateFileButton(_ item: WatchedActivityItem) -> some View {
        Button {
            appState.openUpdate(item)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayName)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(item.contextLabel)
                        Text("•")
                        Text(item.detectedAt, style: .relative)
                    }
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

    private func openDocumentButton(
        _ item: OpenDocumentItem,
        position: Int
    ) -> some View {
        let isCurrent = appState.currentFile?.path == item.path
        let hasUpdate = appState.unreadUpdate(for: item.path) != nil
        let showsShortcut = modifierKeys.isCommandPressed && position <= 9
        return Button {
            appState.openDocument(item)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isCurrent ? "doc.text.fill" : "doc.text")
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(item.displayName)
                            .fontWeight(isCurrent ? .semibold : .regular)
                            .lineLimit(1)
                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(appState.documentDisplayPath(item))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                if hasUpdate {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .opacity(showsShortcut ? 0 : 1)
                        .accessibilityLabel("Unread update")
                        .help("Changed on disk since you last opened it")
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrent ? Color.accentColor.opacity(0.12) : .clear)
            )
            .overlay(alignment: .trailing) {
                if showsShortcut {
                    Text("⌘\(position)")
                        .font(.caption.monospacedDigit())
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            .regularMaterial,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .padding(.trailing, 4)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: showsShortcut)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(
            position <= 9 ? "Open with Command \(position)" : ""
        )
        .help(
            position <= 9
                ? "\(item.path)\nOpen with ⌘\(position)"
                : item.path
        )
        .contextMenu {
            Button(item.isPinned ? "Unpin" : "Pin") {
                appState.togglePin(item)
            }
            if let index = appState.openDocuments.firstIndex(of: item), index > 0 {
                Button("Move Up") {
                    appState.moveOpenDocument(item, by: -1)
                }
            }
            if let index = appState.openDocuments.firstIndex(of: item),
               index < appState.openDocuments.count - 1 {
                Button("Move Down") {
                    appState.moveOpenDocument(item, by: 1)
                }
            }
            Divider()
            Button("Copy Path") {
                copyPath(item.url)
            }
            Button("Reveal in Finder") {
                revealInFinder(item.url)
            }
            Divider()
            Button("Close", role: .destructive) {
                appState.closeOpenDocument(item)
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
                        appState.openBookmark(file)
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

                Button {
                    appState.showProjectSearch(project)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Search Markdown in \(project.displayName)")

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
                documentIdentifier: appState.currentFile?.standardizedFileURL.path,
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
