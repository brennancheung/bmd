import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @State private var defaultAppStatus = ""
    @State private var isSettingDefaultApp = false

    var body: some View {
        Form {
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

            Section("New Window") {
                Stepper(
                    "Width: \(Int(preferences.windowWidth)) pt",
                    value: $preferences.windowWidth,
                    in: AppPreferences.Limits.windowWidth,
                    step: 50
                )
                Stepper(
                    "Height: \(Int(preferences.windowHeight)) pt",
                    value: $preferences.windowHeight,
                    in: AppPreferences.Limits.windowHeight,
                    step: 50
                )
                Toggle("Center on the current display", isOn: $preferences.centerWindow)
                Text("Window size changes apply the next time bmd opens.")
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
        .frame(width: 520, height: 580)
        .padding(.vertical, 12)
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
