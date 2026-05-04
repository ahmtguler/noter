import AppKit
import KeyboardShortcuts
import SwiftUI

/// Standard macOS Settings pane. Lets the user pick the vault folder, change
/// the subfolder name, and rebind the global hotkey.
struct PreferencesView: View {
    @ObservedObject var app: AppViewModel

    @AppStorage(SettingsKey.subfolder) private var subfolder = SettingsKey.defaultSubfolder
    @State private var vaultDisplay = ""

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

            Section("Shortcut") {
                LabeledContent("Toggle Noter") {
                    KeyboardShortcuts.Recorder(for: .toggleNoter)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 320)
        .onAppear { refreshVaultDisplay() }
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
        if let url = VaultBookmark.resolve() {
            vaultDisplay = url.path
        } else {
            vaultDisplay = ""
        }
    }
}
