import AppKit
import KeyboardShortcuts
import SwiftUI

/// First-launch flow: pick the vault, set the subfolder, record the hotkey.
struct FirstLaunchView: View {
    @ObservedObject var app: AppViewModel

    @AppStorage(SettingsKey.subfolder) private var subfolder = SettingsKey.defaultSubfolder
    @State private var vaultPath = ""

    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Noter")
                    .font(.title.weight(.semibold))
                Text("A popup notes app that stores plain markdown files inside your Obsidian vault.")
                    .foregroundStyle(.secondary)
            }

            GroupBox("Vault folder") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(vaultPath.isEmpty ? "Not chosen yet" : vaultPath)
                            .truncationMode(.middle)
                            .lineLimit(1)
                            .foregroundStyle(vaultPath.isEmpty ? .secondary : .primary)
                        Spacer()
                        Button("Choose…") { pickVault() }
                    }
                    HStack {
                        Text("Subfolder")
                        TextField("Subfolder", text: $subfolder)
                            .textFieldStyle(.roundedBorder)
                    }
                    Text("New notes save as .md in this subfolder; Obsidian sees them automatically.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            GroupBox("Global hotkey") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Toggle Noter")
                        Spacer()
                        KeyboardShortcuts.Recorder(for: .toggleNoter)
                    }
                    Text("Press this anywhere to summon or hide the notes window.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Get started") { onDone() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(vaultPath.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520, height: 460)
        .onAppear { refreshVaultPath() }
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
            app.reloadVault()
            refreshVaultPath()
        } catch {
            NSLog("[Noter] could not save vault bookmark: \(error)")
        }
    }

    private func refreshVaultPath() {
        if let url = VaultBookmark.resolve() {
            vaultPath = url.path
        } else {
            vaultPath = ""
        }
    }
}
