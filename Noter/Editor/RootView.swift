import SwiftUI

/// Main popup content: title bar at the top with the current note's filename
/// and a pin toggle, the editor in the middle, the formatting toolbar at the
/// bottom. ⌘P brings up the note switcher; ⌘N creates a new note.
struct RootView: View {
    @ObservedObject var app: AppViewModel
    @State private var showSwitcher = false
    @AppStorage(SettingsKey.pinned) private var pinned = false
    @StateObject private var commands = EditorCommands()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                titleBar
                EditorView(text: $app.editor.body, commands: commands)
                ToolbarView(commands: commands)
            }

            if showSwitcher {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { showSwitcher = false }
                SwitcherOverlay(
                    store: app.store,
                    editor: app.editor,
                    isShowing: $showSwitcher
                )
                .padding(.top, 60)
            }
        }
        .background(VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow))
        .background(hiddenShortcuts)
        .frame(minWidth: 380, minHeight: 360)
        .onAppear { ensureAnOpenNote() }
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            // Reserve space for the macOS traffic-light buttons on the left.
            Color.clear.frame(width: 60, height: 1)
            Spacer(minLength: 0)
            Text(currentTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            pinToggle
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
    }

    private var currentTitle: String {
        if let note = app.editor.currentNote {
            return note.title
        }
        return app.editor.body.isEmpty ? "New note" : Slugify.title(from: app.editor.body)
            .nonEmptyOrFallback("New note")
    }

    private var pinToggle: some View {
        Button {
            pinned.toggle()
        } label: {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .foregroundStyle(pinned ? AnyShapeStyle(Color.accentColor) :
                    AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .font(.system(size: 13, weight: .medium))
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pinned ? "Unpin (hide on focus loss)" : "Pin (keep on top)")
    }

    private var hiddenShortcuts: some View {
        ZStack {
            Button("Open switcher") { showSwitcher = true }
                .keyboardShortcut("p", modifiers: .command)
            Button("New note") { createAndOpenNewNote() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Preferences") { PreferencesAction.open() }
                .keyboardShortcut(",", modifiers: .command)
        }
        .buttonStyle(.plain)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func ensureAnOpenNote() {
        if app.editor.currentNote != nil || !app.editor.body.isEmpty { return }
        if let first = app.store.notes.first {
            app.editor.open(first)
        } else {
            app.editor.startBlankDraft()
        }
    }

    private func createAndOpenNewNote() {
        app.editor.startBlankDraft()
    }
}

private extension String {
    func nonEmptyOrFallback(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
