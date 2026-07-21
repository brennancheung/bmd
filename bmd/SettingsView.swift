import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @State private var defaultAppStatus = ""
    @State private var isSettingDefaultApp = false
    @State private var selectedIgnorePatternID: UUID?
    @FocusState private var focusedIgnorePatternID: UUID?

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Color scheme", selection: $preferences.appearance) {
                    ForEach(AppearancePreference.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Reading") {
                preferenceSlider(
                    title: "Default zoom",
                    value: $preferences.zoomPercent,
                    range: AppPreferences.Limits.zoomPercent,
                    step: 5,
                    suffix: "%"
                )
                preferenceSlider(
                    title: "Text width",
                    value: $preferences.proseWidth,
                    range: AppPreferences.Limits.proseWidth,
                    step: 20,
                    suffix: " pt"
                )
                preferenceSlider(
                    title: "Maximum table width",
                    value: $preferences.tableWidth,
                    range: AppPreferences.Limits.tableWidth,
                    step: 20,
                    suffix: " pt"
                )
            }

            Section("Editor") {
                Toggle(
                    "Use Vim keybindings",
                    isOn: $preferences.usesVimEditorBindings
                )
                Text("Adds Vim Normal, Insert, and Visual modes. Use :w to save and :wq to save and return to Preview.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("New Window") {
                Picker("Width", selection: $preferences.windowWidthPreset) {
                    ForEach(WindowWidthPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                Text("bmd opens centered at the full visible height of the current display.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sidebar") {
                preferenceSlider(
                    title: "Section label size",
                    value: $preferences.sidebarSectionHeaderScalePercent,
                    range: AppPreferences.Limits.sidebarSectionHeaderScalePercent,
                    step: 5,
                    suffix: "%"
                )
                countStepper(
                    title: "Updates shown",
                    value: $preferences.updateFileLimit,
                    range: AppPreferences.Limits.updateFileLimit
                )
            }

            Section("File Watching") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ignore patterns")

                    List(selection: $selectedIgnorePatternID) {
                        ForEach($preferences.ignoredPatterns) { $pattern in
                            TextField("Glob pattern", text: $pattern.value)
                                .textFieldStyle(.plain)
                                .focused(
                                    $focusedIgnorePatternID,
                                    equals: pattern.id
                                )
                                .tag(pattern.id)
                                .onTapGesture {
                                    selectedIgnorePatternID = pattern.id
                                }
                        }
                    }
                    .listStyle(.bordered(alternatesRowBackgrounds: true))
                    .frame(minHeight: 120, idealHeight: 140, maxHeight: 180)
                    .onDeleteCommand(perform: removeSelectedIgnorePattern)

                    HStack(spacing: 2) {
                        Button(action: addIgnorePattern) {
                            Image(systemName: "plus")
                                .frame(width: 18, height: 18)
                        }
                        .help("Add ignore pattern")

                        Button(action: removeSelectedIgnorePattern) {
                            Image(systemName: "minus")
                                .frame(width: 18, height: 18)
                        }
                        .disabled(!hasSelectedIgnorePattern)
                        .help("Remove selected ignore pattern")

                        Spacer()
                    }
                    .buttonStyle(.borderless)
                }

                Text("Patterns without a slash match names anywhere. Use *, **, and ? for glob matching. Hidden items and app packages are always ignored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(
                    "Use .gitignore files in projects",
                    isOn: $preferences.usesGitIgnoreFiles
                )
                Text("bmd applies rules from the project root and nested .gitignore files while scanning each folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Default App") {
                Button("Make bmd the Default Markdown App") {
                    setAsDefaultMarkdownApp()
                }
                .disabled(isSettingDefaultApp)

                if !defaultAppStatus.isEmpty {
                    Text(defaultAppStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Restore Defaults") {
                    preferences.resetAll()
                }
            }
        }
        .formStyle(.grouped)
        .frame(
            minWidth: 620,
            idealWidth: 720,
            maxWidth: .infinity,
            minHeight: 600,
            idealHeight: 960,
            maxHeight: .infinity
        )
        .padding(.vertical, 12)
        .onDisappear {
            preferences.removeEmptyIgnorePatterns()
        }
    }

    private var hasSelectedIgnorePattern: Bool {
        guard let selectedIgnorePatternID else { return false }
        return preferences.ignoredPatterns.contains { $0.id == selectedIgnorePatternID }
    }

    private func addIgnorePattern() {
        let id = preferences.addIgnorePattern()
        selectedIgnorePatternID = id
        Task { @MainActor in
            focusedIgnorePatternID = id
        }
    }

    private func removeSelectedIgnorePattern() {
        guard let selectedIgnorePatternID else { return }
        preferences.removeIgnorePattern(id: selectedIgnorePatternID)
        self.selectedIgnorePatternID = nil
        focusedIgnorePatternID = nil
    }

    @ViewBuilder
    private func countStepper(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        LabeledContent(title) {
            Stepper(value: value, in: range) {
                Text("\(value.wrappedValue)")
                    .monospacedDigit()
                    .frame(width: 28, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func preferenceSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        suffix: String
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: value, in: range, step: step)
                    .frame(width: 220)
                Text("\(Int(value.wrappedValue))\(suffix)")
                    .monospacedDigit()
                    .frame(width: 62, alignment: .trailing)
            }
        }
    }

    private func setAsDefaultMarkdownApp() {
        let extensions = ["md", "markdown", "mdown", "mkd", "mdwn"]
        let contentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        guard !contentTypes.isEmpty else {
            defaultAppStatus = "macOS could not resolve the Markdown file type."
            return
        }

        let installedURL = URL(fileURLWithPath: "/Applications/bmd.app", isDirectory: true)
        let applicationURL = FileManager.default.fileExists(atPath: installedURL.path)
            ? installedURL
            : Bundle.main.bundleURL

        isSettingDefaultApp = true
        defaultAppStatus = "Requesting permission from macOS…"

        Task { @MainActor in
            do {
                var seenIdentifiers = Set<String>()
                for contentType in contentTypes
                where seenIdentifiers.insert(contentType.identifier).inserted {
                    try await NSWorkspace.shared.setDefaultApplication(
                        at: applicationURL,
                        toOpen: contentType
                    )
                }
                isSettingDefaultApp = false
                defaultAppStatus = "bmd is now the default app for Markdown files."
            } catch {
                isSettingDefaultApp = false
                defaultAppStatus = "Could not change the default app: \(error.localizedDescription)"
            }
        }
    }
}
