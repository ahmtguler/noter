import SwiftUI

/// Main popup content: the editor on top, the formatting toolbar below.
/// (Switcher overlay and pin button arrive in later commits.)
struct RootView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var editor: EditorState

    var body: some View {
        VStack(spacing: 0) {
            EditorView(text: $editor.body)
            ToolbarView(text: $editor.body)
        }
        .frame(minWidth: 360, minHeight: 320)
        .onAppear { ensureAnOpenNote() }
    }

    private func ensureAnOpenNote() {
        if editor.currentNote != nil { return }
        if let first = store.notes.first {
            editor.open(first)
        } else if let new = try? store.createNote() {
            editor.open(new)
        }
    }
}
