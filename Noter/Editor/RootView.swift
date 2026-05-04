import AppKit
import MarkdownEditor
import SwiftUI

/// Main popup content: title bar at the top with the current note's filename
/// and a pin toggle, the editor in the middle, the formatting toolbar at the
/// bottom. ⌘P brings up the note switcher; ⌘N creates a new note.
struct RootView: View {
    @ObservedObject var app: AppViewModel
    @State private var showSwitcher = false
    @StateObject private var commandsHolder = CommandsHolder()
    @AppStorage(SettingsKey.pinned) private var pinned = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                titleBar
                MarkdownEditor(
                    text: $app.editor.body,
                    configuration: editorConfiguration
                ) { commands in
                    commandsHolder.commands = commands
                }
                Group {
                    if let commands = commandsHolder.commands {
                        ToolbarView(commands: commands)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }

            if showSwitcher {
                ZStack {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { showSwitcher = false }
                    SwitcherOverlay(
                        store: app.store,
                        editor: app.editor,
                        isShowing: $showSwitcher
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onReceive(NotificationCenter.default.publisher(for: .noterShowSwitcher)) { _ in
            showSwitcher = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .noterNewNote)) { _ in
            createAndOpenNewNote()
        }
        .onReceive(NotificationCenter.default.publisher(for: .noterShowPreferences)) { _ in
            PreferencesAction.open()
        }
    }

    private var editorConfiguration: EditorConfiguration {
        EditorConfiguration(
            theme: .system,
            fontSize: 14,
            spellCheck: true,
            smartListContinuation: true,
            revealMarkersOnCursor: true,
            lineWrap: true,
            contentPadding: 24
        )
    }

    private var titleBar: some View {
        ZStack {
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
        // ⌘N / ⌘P / ⌘, are intercepted by `PanelKeyMonitor` (a local
        // NSEvent monitor) before they can reach the WKWebView, then
        // delivered as notifications observed by this view. The hidden
        // SwiftUI shortcut buttons aren't enough on their own because the
        // web view's content will swallow the event first.
        EmptyView()
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

/// Holds the `MarkdownCommands` produced by the editor once it's mounted.
/// The view binds to it via @StateObject so the toolbar updates as soon as
/// the editor publishes its commands.
@MainActor
final class CommandsHolder: ObservableObject {
    @Published var commands: MarkdownCommands?
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
