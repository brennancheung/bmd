import AppKit
import SwiftUI

@MainActor
private final class QuickSwitcherKeyMonitor: ObservableObject {
    private var monitor: Any?

    func start(handler: @escaping (NSEvent) -> Bool) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event) ? nil : event
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}

struct QuickSwitcherView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @FocusState private var searchIsFocused: Bool
    @StateObject private var keyMonitor = QuickSwitcherKeyMonitor()
    @State private var query = ""
    @State private var selection: String?
    @State private var candidates: [DocumentCandidate] = []
    @State private var hasManuallyMovedSelection = false

    private var searchPlaceholder: String {
        switch appState.quickSwitcherScope {
        case .global:
            "Search Markdown in all projects"
        case let .project(project):
            "Search Markdown in \(project.displayName)"
        case .unavailableProject:
            "Search current project"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider()
            searchResults
            Divider()
            keyboardHelp
        }
        .onAppear {
            refreshCandidates()
            selection = candidates.first?.path
            searchIsFocused = true
            keyMonitor.start { event in
                handleKeyEvent(event)
            }
        }
        .onDisappear {
            keyMonitor.stop()
        }
        .onChange(of: query) {
            refreshCandidates()
            if !hasManuallyMovedSelection
                || !candidates.contains(where: { $0.path == selection }) {
                selection = candidates.first?.path
            }
        }
        .onChange(of: appState.quickSwitcherScope) {
            query = ""
            hasManuallyMovedSelection = false
            refreshCandidates()
            selection = candidates.first?.path
            searchIsFocused = !isProjectUnavailable
        }
        .onChange(of: appState.indexedFilesByProject) {
            refreshCandidates()
            if !candidates.contains(where: { $0.path == selection }) {
                selection = candidates.first?.path
            }
        }
        .onExitCommand {
            dismiss()
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(searchPlaceholder, text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchIsFocused)
                .onSubmit(openSelection)
                .disabled(isProjectUnavailable)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear Search")
            }
            scopeLabel
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    @ViewBuilder
    private var searchResults: some View {
        if case let .unavailableProject(file) = appState.quickSwitcherScope {
            unavailableProjectView(file: file)
        } else if candidates.isEmpty, query.isEmpty {
            searchPromptView
        } else if candidates.isEmpty {
            ContentUnavailableView.search(text: query)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            resultList
        }
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            List(candidates, selection: $selection) { candidate in
                Button {
                    open(candidate)
                } label: {
                    candidateRow(candidate)
                }
                .buttonStyle(.plain)
                .tag(candidate.path)
                .id(candidate.path)
            }
            .listStyle(.inset)
            .onChange(of: selection) {
                guard let selection else { return }
                withAnimation(.easeOut(duration: 0.08)) {
                    proxy.scrollTo(selection, anchor: .center)
                }
            }
        }
    }

    private func candidateRow(_ candidate: DocumentCandidate) -> some View {
        HStack(spacing: 10) {
            Image(systemName: candidate.source.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                highlightedText(
                    candidate.displayName,
                    ranges: candidate.displayNameMatchRanges
                )
                .fontWeight(.medium)
                .lineLimit(1)
                highlightedText(
                    candidate.contextLabel,
                    ranges: candidate.contextMatchRanges
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if candidate.hasUnreadUpdate {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Unread update")
                    .help("Changed on disk since you last opened it")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var keyboardHelp: some View {
        HStack {
            Text("↑↓ or ⌃J ⌃K to select  •  Return to open  •  Esc to close")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("⌘↑ first  •  ⌘↓ last")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var isProjectUnavailable: Bool {
        if case .unavailableProject = appState.quickSwitcherScope { return true }
        return false
    }

    private var scopeLabel: some View {
        HStack(spacing: 5) {
            Image(
                systemName: appState.quickSwitcherScope == .global
                    ? "square.grid.2x2"
                    : "folder"
            )
            Text(appState.quickSwitcherScope.title)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
        .accessibilityLabel("Search scope: \(appState.quickSwitcherScope.title)")
    }

    private var searchPromptView: some View {
        ContentUnavailableView {
            Label(
                "Search \(appState.quickSwitcherScope.title)",
                systemImage: "doc.text.magnifyingglass"
            )
        } description: {
            Text("Type part of a filename or its project-relative path.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func unavailableProjectView(file: URL?) -> some View {
        ContentUnavailableView {
            Label(
                file == nil ? "No Active Document" : "No Project for This Document",
                systemImage: "folder.badge.questionmark"
            )
        } description: {
            if let file {
                Text("\(file.lastPathComponent) is not inside a project added to bmd.")
            } else {
                Text("Open a Markdown document or search a project from the sidebar.")
            }
        } actions: {
            if file != nil {
                Button("Add Enclosing Folder as Project") {
                    appState.addCurrentDocumentFolderAsProject()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openSelection() {
        guard let selection,
              let candidate = candidates.first(where: { $0.path == selection }) else {
            return
        }
        open(candidate)
    }

    private func refreshCandidates() {
        candidates = appState.quickSwitcherCandidates(query: query)
    }

    private func open(_ candidate: DocumentCandidate) {
        appState.openFile(candidate.url)
        dismiss()
    }

    private func moveSelection(by offset: Int) {
        guard !candidates.isEmpty else { return }
        let currentIndex = candidates.firstIndex(where: { $0.path == selection }) ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), candidates.count - 1)
        hasManuallyMovedSelection = true
        selection = candidates[nextIndex].path
    }

    private func moveSelectionToBoundary(first: Bool) {
        guard let candidate = first ? candidates.first : candidates.last else { return }
        hasManuallyMovedSelection = true
        selection = candidate.path
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])

        if modifiers == .control {
            switch event.keyCode {
            case 38:
                moveSelection(by: 1)
                return true
            case 40:
                moveSelection(by: -1)
                return true
            default:
                return false
            }
        }

        if modifiers == .command {
            switch event.keyCode {
            case 126:
                moveSelectionToBoundary(first: true)
                return true
            case 125:
                moveSelectionToBoundary(first: false)
                return true
            default:
                return false
            }
        }

        guard modifiers.isEmpty else { return false }
        switch event.keyCode {
        case 126:
            moveSelection(by: -1)
            return true
        case 125:
            moveSelection(by: 1)
            return true
        case 116:
            moveSelection(by: -8)
            return true
        case 121:
            moveSelection(by: 8)
            return true
        case 36, 76:
            openSelection()
            return true
        case 53:
            dismiss()
            return true
        default:
            return false
        }
    }

    private func highlightedText(
        _ value: String,
        ranges: [FuzzyMatchRange]
    ) -> Text {
        let highlightedIndices = Set(ranges.flatMap { range in
            range.start..<(range.start + range.length)
        })
        return Array(value).enumerated().reduce(Text("")) { text, item in
            let segment = Text(String(item.element))
            if highlightedIndices.contains(item.offset) {
                return text + segment
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            return text + segment
        }
    }
}
