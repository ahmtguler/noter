import AppKit
import KeyboardShortcuts
import SwiftUI

/// macOS Preferences pane. Lets the user pick the vault folder, change the
/// subfolder name, rebind the global hotkey, set behavioural toggles, and
/// pick the editor's appearance theme.
struct PreferencesView: View {
    @ObservedObject var app: AppViewModel

    @AppStorage(SettingsKey.subfolder) private var subfolder = SettingsKey.defaultSubfolder
    @AppStorage(SettingsKey.idleNewNoteMinutes)
    private var idleNewNoteMinutes = SettingsKey.defaultIdleNewNoteMinutes
    @AppStorage(SettingsKey.showFormattingToolbar)
    private var showFormattingToolbar = SettingsKey.defaultShowFormattingToolbar
    @AppStorage(SettingsKey.editorTheme)
    private var editorThemeRaw = SettingsKey.defaultEditorTheme
    @AppStorage(SettingsKey.editorFontSize)
    private var editorFontSizeRaw = SettingsKey.defaultEditorFontSize
    @State private var vaultDisplay = ""

    private let idleHelp = """
    After the popup has been hidden this long, the next time you open it you'll get a blank draft instead of \
    resuming the last note. Set to 0 to always resume.
    """

    var body: some View {
        Form {
            Section("Vault") {
                LabeledContent("Folder") {
                    HStack(spacing: 8) {
                        Text(vaultDisplay.isEmpty ? "Not configured" : vaultDisplay)
                            .truncationMode(.middle)
                            .lineLimit(1)
                            .foregroundStyle(vaultDisplay.isEmpty ? .secondary : .primary)
                        Spacer(minLength: 8)
                        Button("Choose…") { pickVault() }
                    }
                }
                LabeledContent("Subfolder") {
                    TextField("Subfolder", text: $subfolder)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { app.reloadVault() }
                }
                Text("Notes are saved as .md files in this subfolder so Obsidian sees them automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Theme", selection: themeBinding) {
                    ForEach(EditorAppearancePreference.allCases) { preference in
                        Text(preference.label).tag(preference)
                    }
                }
                .pickerStyle(.segmented)
                Text("Match system follows your macOS appearance setting.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("Font size", selection: fontSizeBinding) {
                    ForEach(EditorFontSizePreference.allCases) { preference in
                        Text(preference.label).tag(preference)
                    }
                }
                .pickerStyle(.segmented)
                Text("Headings scale with the body size.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcut") {
                LabeledContent("Toggle Noter") {
                    KeyboardShortcuts.Recorder(for: .toggleNoter)
                }
            }

            Section("Behavior") {
                LabeledContent("Reset to a fresh note after") {
                    HStack(spacing: 6) {
                        Stepper(
                            value: $idleNewNoteMinutes,
                            in: 0 ... 240,
                            step: 1
                        ) {
                            Text("\(idleNewNoteMinutes) min")
                                .monospacedDigit()
                                .frame(minWidth: 60, alignment: .leading)
                        }
                    }
                }
                Text(idleHelp)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Show formatting toolbar", isOn: $showFormattingToolbar)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 520)
        .onAppear { refreshVaultDisplay() }
    }

    /// Bridges the raw-string @AppStorage to the strongly-typed enum the Picker uses.
    private var themeBinding: Binding<EditorAppearancePreference> {
        Binding(
            get: { EditorAppearancePreference(rawValue: editorThemeRaw) ?? .system },
            set: { editorThemeRaw = $0.rawValue }
        )
    }

    private var fontSizeBinding: Binding<EditorFontSizePreference> {
        Binding(
            get: { EditorFontSizePreference(rawValue: editorFontSizeRaw) ?? .medium },
            set: { editorFontSizeRaw = $0.rawValue }
        )
    }

    private func pickVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose your Obsidian vault folder"
        panel.prompt = "Select Vault"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try VaultBookmark.save(url)
            refreshVaultDisplay()
            app.reloadVault()
        } catch {
            NSLog("[Noter] could not save vault bookmark: \(error)")
        }
    }

    private func refreshVaultDisplay() {
        // displayPath, not resolve: this runs on every appearance just to show
        // a string, and resolve acquires a security scope that is never given
        // back.
        vaultDisplay = VaultBookmark.displayPath() ?? ""
    }
}
