import SwiftUI

/// Main popup content: the editor on top, the formatting toolbar below.
/// ⌘P brings up the note switcher; ⌘N creates a new note. The pin button in
/// the top-right corner overrides hide-on-blur.
struct RootView: View {
    @ObservedObject var app: AppViewModel
    @State private var showSwitcher = false
    @AppStorage(SettingsKey.pinned) private var pinned = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                EditorView(text: $app.editor.body)
                ToolbarView(text: $app.editor.body)
            }

            pinToggle
                .padding(.top, 8)
                .padding(.trailing, 12)

            if showSwitcher {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { showSwitcher = false }
                SwitcherOverlay(
                    store: app.store,
                    editor: app.editor,
                    isShowing: $showSwitcher
                )
            }
        }
        .frame(minWidth: 360, minHeight: 320)
        .background(hiddenShortcuts)
        .onAppear { ensureAnOpenNote() }
    }

    private var pinToggle: some View {
        Button {
            pinned.toggle()
        } label: {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .foregroundStyle(pinned ? AnyShapeStyle(Color.accentColor) :
                    AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .font(.system(size: 14, weight: .medium))
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
        }
        .buttonStyle(.plain)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func ensureAnOpenNote() {
        if app.editor.currentNote != nil { return }
        if let first = app.store.notes.first {
            app.editor.open(first)
        } else {
            createAndOpenNewNote()
        }
    }

    private func createAndOpenNewNote() {
        app.editor.flush()
        if let new = try? app.store.createNote() {
            app.editor.open(new)
        }
    }
}
