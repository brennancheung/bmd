import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView()
        }
        .navigationTitle(appState.currentTitle)
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
                        appState.pinFolder(url)
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

            Section("Pinned folders") {
                if appState.pins.isEmpty {
                    Text("Pin agent output folders")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.pins) { pin in
                        DisclosureGroup {
                            let files = appState.markdownFiles(inFolder: pin)
                            if files.isEmpty {
                                Text("No .md files")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(files, id: \.path) { file in
                                    Button {
                                        appState.openFile(file)
                                    } label: {
                                        Text(file.lastPathComponent)
                                            .lineLimit(1)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } label: {
                            Label(pin.displayName, systemImage: "folder")
                        }
                        .contextMenu {
                            Button("Unpin", role: .destructive) {
                                appState.unpin(pin)
                            }
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([pin.url])
                            }
                        }
                    }
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
                    appState.presentPinFolderPanel()
                } label: {
                    Label("Pin folder", systemImage: "pin")
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

struct DetailView: View {
    @EnvironmentObject private var appState: AppState

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
                renderToken: appState.renderToken
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
