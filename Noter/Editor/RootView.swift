import AppKit
import MarkdownEditor
import SwiftUI

/// Hosts `RootView` and keeps it supplied with the *live* `EditorState`.
///
/// `PanelController` builds its `NSHostingView` exactly once and never
/// reassigns `rootView`, so a `RootView` that resolved `app.editor` inside its
/// own `init` stayed bound to whichever instance existed the first time the
/// popup was shown. `AppViewModel.reloadVault()` replaces both the store and
/// the editor when the vault changes, which left every keystroke, new note and
/// title-driven rename going to the *previous* vault for the rest of the
/// session while the switcher listed the new one.
///
/// Resolving `app.editor` here instead means the lookup re-runs whenever
/// `AppViewModel` publishes, so `RootView`'s observation follows the swap.
struct RootContainerView: View {
    @ObservedObject var app: AppViewModel

    var body: some View {
        RootView(app: app, editor: app.editor)
    }
}

/// Main popup content: title bar at the top with the current note's filename
/// and a pin toggle, the editor in the middle, the formatting toolbar at the
/// bottom. ⌘P brings up the note switcher; ⌘N creates a new note.
struct RootView: View {
    @ObservedObject var app: AppViewModel
    /// Observe the EditorState directly. Without this, mutations like
    /// `editor.body = ""` (from ⌘N → startBlankDraft) only fire
    /// `editor.objectWillChange` — which `app` doesn't propagate, so
    /// RootView's body never re-evaluates and the WKWebView keeps showing
    /// the old text until some other state change forces a redraw.
    @ObservedObject var editor: EditorState
    @State private var showSwitcher = false
    @State private var showCommandPalette = false
    @StateObject private var commandsHolder = CommandsHolder()
    @AppStorage(SettingsKey.pinned) private var pinned = false
    @AppStorage(SettingsKey.showFormattingToolbar)
    private var showFormattingToolbar = SettingsKey.defaultShowFormattingToolbar
    @AppStorage(SettingsKey.editorTheme)
    private var editorThemeRaw = SettingsKey.defaultEditorTheme
    @AppStorage(SettingsKey.editorFontSize)
    private var editorFontSizeRaw = SettingsKey.defaultEditorFontSize
    @Environment(\.colorScheme) private var systemColorScheme

    init(app: AppViewModel, editor: EditorState) {
        self.app = app
        _editor = ObservedObject(wrappedValue: editor)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                titleBar
                MarkdownEditor(
                    text: $editor.body,
                    configuration: editorConfiguration,
                    onCommandsReady: { commands in
                        commandsHolder.commands = commands
                    },
                    onOpenURL: { url in
                        // NSWorkspace.open returns -50 (paramErr) when the
                        // string lacks a scheme — e.g. user wrote
                        // "google.com" rather than "https://google.com".
                        // Auto-prefix https:// for those, and url-encode any
                        // raw spaces / unicode that NSURL would otherwise
                        // refuse.
                        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
                        let withScheme = trimmed.contains("://")
                            ? trimmed
                            : "https://" + trimmed
                        let allowed = CharacterSet.urlQueryAllowed
                            .union(.init(charactersIn: "#:/?&=+%"))
                        let encoded = withScheme
                            .addingPercentEncoding(withAllowedCharacters: allowed) ?? withScheme
                        guard let resolved = URL(string: encoded) else { return }
                        NSWorkspace.shared.open(resolved)
                    }
                )
                if showFormattingToolbar {
                    Group {
                        if let commands = commandsHolder.commands {
                            ToolbarView(commands: commands)
                        } else {
                            Color.clear.frame(height: 36)
                        }
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
                        editor: editor,
                        isShowing: $showSwitcher
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if showCommandPalette {
                ZStack {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { showCommandPalette = false }
                    CommandPaletteOverlay(
                        store: app.store,
                        editor: editor,
                        isShowing: $showCommandPalette,
                        onShowSwitcher: { showSwitcher = true },
                        onShowPreferences: {
                            NotificationCenter.default.post(
                                name: .noterShowPreferences,
                                object: nil
                            )
                        }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(
            ZStack {
                // Behind-window blur preserves the popup feel.
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                // Theme-tinted overlay cuts the see-through so content reads
                // cleanly even over busy wallpapers.
                overlayColor
            }
            .ignoresSafeArea()
        )
        .preferredColorScheme(themePreference.colorScheme)
        .background(hiddenShortcuts)
        .ignoresSafeArea()
        .frame(minWidth: 380, minHeight: 360)
        .onAppear { ensureAnOpenNote() }
        .onChange(of: editorFontSizeRaw) { _, _ in resizeWindowIfAtDefault() }
        // Opening a note from ⌘P (or dismissing either overlay) should hand
        // keyboard focus back to the editor. The overlay's text field held the
        // window's first responder, so the editor needs to reclaim it.
        .onChange(of: showSwitcher) { _, shown in
            syncEditorCursorSuppression()
            if !shown { focusEditorAfterOverlay() }
        }
        .onChange(of: showCommandPalette) { _, shown in
            syncEditorCursorSuppression()
            if !shown { focusEditorAfterOverlay() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .noterShowSwitcher)) { _ in
            showCommandPalette = false
            showSwitcher = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .noterShowCommandPalette)) { _ in
            showSwitcher = false
            showCommandPalette = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .noterNewNote)) { _ in
            // Dismiss any floating overlay so the new note actually appears
            // in front; otherwise the palette would stay covering the editor.
            showCommandPalette = false
            showSwitcher = false
            createAndOpenNewNote()
        }
        .onReceive(NotificationCenter.default.publisher(for: .noterShowPreferences)) { _ in
            showCommandPalette = false
            showSwitcher = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .noterFocusEditor)) { _ in
            // Don't pull focus out of a floating overlay's search/key field.
            guard !showSwitcher, !showCommandPalette else { return }
            commandsHolder.commands?.focus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .noterDeleteActiveNote)) { _ in
            // ⇧⌘⌫ targets the switcher's highlighted row (handled in the
            // overlay) or the open note when no overlay is up. The ⌘K palette
            // has its own Delete row, so the chord is inert while it's shown.
            guard !showSwitcher, !showCommandPalette else { return }
            deleteCurrentNote()
        }
        // .noterShowPreferences is handled by AppDelegate via its
        // PreferencesWindowController — no observer needed here.
    }

    private var themePreference: EditorAppearancePreference {
        EditorAppearancePreference(rawValue: editorThemeRaw) ?? .system
    }

    /// Resolves "system" against the SwiftUI environment so the overlay color
    /// always matches the actual rendered appearance.
    private var effectiveColorScheme: ColorScheme {
        themePreference.colorScheme ?? systemColorScheme
    }

    private var overlayColor: Color {
        switch effectiveColorScheme {
        case .light: Color.white.opacity(0.55)
        case .dark: Color.black.opacity(0.45)
        @unknown default: Color.black.opacity(0.45)
        }
    }

    private var fontSizePreference: EditorFontSizePreference {
        EditorFontSizePreference(rawValue: editorFontSizeRaw) ?? .medium
    }

    private var editorConfiguration: EditorConfiguration {
        // Resolve `.system` to a concrete `.light` / `.dark` here so the JS
        // side never has to query `window.matchMedia` — WKWebView's
        // `prefers-color-scheme` lags behind appearance flips, which left
        // the editor text mismatched right after the user switched themes.
        let resolvedTheme: EditorConfiguration.Theme =
            effectiveColorScheme == .dark ? .dark : .light
        return EditorConfiguration(
            theme: resolvedTheme,
            fontSize: fontSizePreference.pointSize,
            spellCheck: true,
            smartListContinuation: true,
            revealMarkersOnCursor: true,
            lineWrap: true,
            contentPadding: 24
        )
    }

    private var titleBar: some View {
        ZStack {
            WindowDragRegion(onDoubleClick: snapToTopRight)
            HStack(spacing: 6) {
                Spacer(minLength: 12)
                Text(currentTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 12)
            }
            // Let drags and double-clicks pass through the centered title
            // text to the WindowDragRegion behind it. Without this the
            // SwiftUI Text view eats clicks that land on the title.
            .allowsHitTesting(false)
            HStack {
                closeButton
                Spacer()
                pinToggle
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 36)
    }

    /// Snaps the popup to a fixed top-right slot on the active screen.
    /// Window size scales with the chosen font size so the layout stays
    /// proportional. `visibleFrame` already excludes the menu bar.
    private func snapToTopRight() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible })
        else { return }
        let screen = window.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = snapTargetSize
        let margin: CGFloat = 16
        let origin = NSPoint(
            x: visible.maxX - size.width - margin,
            y: visible.maxY - size.height - margin
        )
        let frame = NSRect(origin: origin, size: size)
        window.setFrame(frame, display: true, animate: true)
    }

    private var snapTargetSize: NSSize {
        defaultSize(for: fontSizePreference)
    }

    private func defaultSize(for pref: EditorFontSizePreference) -> NSSize {
        switch pref {
        case .small: NSSize(width: 480, height: 640)
        case .medium: NSSize(width: 540, height: 700)
        case .large: NSSize(width: 600, height: 760)
        }
    }

    /// If the window is currently sized to one of the predefined defaults,
    /// auto-resize to the new font preference's default. If the user has
    /// manually resized to a custom size, leave it alone. The top-right
    /// corner is held fixed so the resize feels anchored where the user
    /// last placed it; the result is then clamped to the visible screen.
    private func resizeWindowIfAtDefault() {
        // Look up the popup by type — when the user changes font size from
        // the Preferences window, NSApp.keyWindow is the prefs window, not
        // the popup, so a generic "first visible" lookup would resize the
        // wrong window.
        guard let window = NSApp.windows.first(where: { $0 is PopupPanel }) else { return }
        let currentSize = window.frame.size
        let isAtKnownDefault = EditorFontSizePreference.allCases.contains { pref in
            let target = defaultSize(for: pref)
            return abs(currentSize.width - target.width) < 0.5 &&
                abs(currentSize.height - target.height) < 0.5
        }
        guard isAtKnownDefault else { return }

        let newSize = snapTargetSize
        let topRight = NSPoint(x: window.frame.maxX, y: window.frame.maxY)
        var newFrame = NSRect(
            origin: NSPoint(x: topRight.x - newSize.width, y: topRight.y - newSize.height),
            size: newSize
        )

        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            if newFrame.maxX > visible.maxX {
                newFrame.origin.x = visible.maxX - newFrame.width
            }
            if newFrame.minX < visible.minX {
                newFrame.origin.x = visible.minX
            }
            if newFrame.maxY > visible.maxY {
                newFrame.origin.y = visible.maxY - newFrame.height
            }
            if newFrame.minY < visible.minY {
                newFrame.origin.y = visible.minY
            }
        }
        window.setFrame(newFrame, display: true, animate: true)
    }

    private var currentTitle: String {
        let raw: String = if let note = editor.currentNote {
            note.title
        } else {
            Slugify.title(from: editor.body)
        }
        let display = raw.isEmpty ? "New note" : raw
        // Hard character cap on the title bar so very long first lines
        // don't dominate the popup chrome; SwiftUI's middle-truncation
        // would only kick in based on rendered width and varies with
        // window size — the user wants a stable 28-chars + ellipsis.
        let limit = 30
        if display.count <= limit { return display }
        let stop = display.index(display.startIndex, offsetBy: 28)
        return display[..<stop] + "…"
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
        if editor.currentNote != nil || !editor.body.isEmpty { return }
        if let first = app.store.notes.first {
            editor.open(first)
        } else {
            editor.startBlankDraft()
        }
    }

    private func createAndOpenNewNote() {
        editor.startBlankDraft()
    }

    /// Refocus the editor once no overlay is up. Guarded so closing the palette
    /// to open the switcher (or deleting a note while the switcher stays open)
    /// doesn't yank focus out from under the still-visible overlay. Deferred a
    /// tick so the overlay's text field has fully resigned first responder.
    private func focusEditorAfterOverlay() {
        guard !showSwitcher, !showCommandPalette else { return }
        let commands = commandsHolder.commands
        DispatchQueue.main.async { commands?.focus() }
    }

    /// Tell the editor to drop its I-beam cursor whenever a floating overlay
    /// covers it, and restore it once both are dismissed. Without this the
    /// WKWebView keeps asserting CodeMirror's text cursor under the pointer and
    /// it flickers against the overlay's arrow. Idempotent, so it's safe to
    /// call from both overlays' onChange even as they hand off to each other.
    private func syncEditorCursorSuppression() {
        commandsHolder.commands?.setCursorSuppressed(showSwitcher || showCommandPalette)
    }

    /// ⇧⌘⌫ on the open note: move it to Recently Deleted, then fall back to the
    /// next note (or a fresh draft). No-op on an unsaved blank draft — there's
    /// nothing on disk to remove, so `currentNote` is nil.
    private func deleteCurrentNote() {
        guard let note = editor.currentNote else { return }
        do {
            try editor.delete(note)
        } catch {
            NSLog("[Noter] delete failed: \(error)")
        }
    }
}

/// Holds the `MarkdownCommands` produced by the editor once it's mounted.
/// The view binds to it via @StateObject so the toolbar updates as soon as
/// the editor publishes its commands.
@MainActor
final class CommandsHolder: ObservableObject {
    @Published var commands: MarkdownCommands?
}

/// Lets the title bar serve as a window-drag handle. We can't use
/// `mouseDownCanMoveWindow` here because we also need to detect a double
/// click on the bar — that flag short-circuits AppKit's mouse delivery, so
/// `mouseDown(with:)` would never fire with a clickCount > 1. Instead we
/// handle mouseDown manually: clickCount 2 snaps to the top-right slot,
/// anything else delegates to `NSWindow.performDrag(with:)`.
private struct WindowDragRegion: NSViewRepresentable {
    var onDoubleClick: () -> Void

    func makeNSView(context _: Context) -> NSView {
        let view = DragView()
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        (nsView as? DragView)?.onDoubleClick = onDoubleClick
    }

    private final class DragView: NSView {
        var onDoubleClick: (() -> Void)?

        override func mouseDown(with event: NSEvent) {
            if event.clickCount >= 2 {
                onDoubleClick?()
                return
            }
            window?.performDrag(with: event)
        }
    }
}
