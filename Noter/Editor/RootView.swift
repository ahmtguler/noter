import AppKit
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
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
        .background(hiddenShortcuts)
        .ignoresSafeArea()
        .frame(minWidth: 380, minHeight: 360)
        .onAppear { ensureAnOpenNote() }
    }

    private var titleBar: some View {
        ZStack {
            // Drag region: the entire title bar is grabbable.
            WindowDragRegion()
            HStack(spacing: 6) {
                Spacer(minLength: 12)
                Text(currentTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 12)
            }
            HStack {
                closeButton
                Spacer()
                pinToggle
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 36)
    }

    private var currentTitle: String {
        if let note = app.editor.currentNote {
            return note.title
        }
        let derived = Slugify.title(from: app.editor.body)
        return derived.isEmpty ? "New note" : derived
    }

    private var pinToggle: some View {
        Button {
            pinned.toggle()
        } label: {
            Image(systemName: pinned ? "pin.fill" : "pin")
                .foregroundStyle(pinned ? AnyShapeStyle(Color.accentColor) :
                    AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pinned ? "Unpin (hide on focus loss)" : "Pin (keep on top)")
    }

    private var closeButton: some View {
        Button {
            NSApp.keyWindow?.orderOut(nil)
        } label: {
            Image(systemName: "xmark")
                .foregroundStyle(.secondary)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("w", modifiers: .command)
        .help("Hide (⌘W)")
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

/// Lets the title bar serve as a window-drag handle. AppKit normally provides
/// this via the title bar; since we hide the buttons and draw our own bar,
/// we re-expose the drag affordance with `mouseDownCanMoveWindow = true`.
private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        DragView()
    }

    func updateNSView(_: NSView, context _: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool {
            true
        }
    }
}
