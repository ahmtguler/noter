import SwiftUI

/// Main popup content: the editor on top, the formatting toolbar below.
/// ⌘P brings up the note switcher; ⌘N creates a new note.
struct RootView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var editor: EditorState
    @State private var showSwitcher = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                EditorView(text: $editor.body)
                ToolbarView(text: $editor.body)
            }

            if showSwitcher {
                Color.black.opacity(0.001) // catches taps to dismiss
                    .contentShape(Rectangle())
                    .onTapGesture { showSwitcher = false }
                SwitcherOverlay(
                    store: store,
                    editor: editor,
                    isShowing: $showSwitcher
                )
            }
        }
        .frame(minWidth: 360, minHeight: 320)
        .background(hiddenShortcuts)
        .onAppear { ensureAnOpenNote() }
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
        if editor.currentNote != nil { return }
        if let first = store.notes.first {
            editor.open(first)
        } else {
            createAndOpenNewNote()
        }
    }

    private func createAndOpenNewNote() {
        editor.flush()
        if let new = try? store.createNote() {
            editor.open(new)
        }
    }
}
