import SwiftUI

/// ⌘K command palette. Floats over the editor as a thin list of actions
/// the user can run against the current note or the app. Same chrome as
/// the note switcher (search field + filtered list + arrow nav + Enter).
struct CommandPaletteOverlay: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var editor: EditorState
    @Binding var isShowing: Bool
    var onShowSwitcher: () -> Void
    var onShowPreferences: () -> Void

    @State private var selectedIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(allCommands.enumerated()), id: \.element.id) { index, command in
                            CommandRow(
                                command: command,
                                isSelected: index == selectedIndex
                            )
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedIndex = index
                                commitSelection()
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .background(ArrowCursorArea())
                .onChange(of: selectedIndex) { _, new in
                    proxy.scrollTo(new, anchor: .center)
                }
            }
            .background(KeyCatcher(
                onMoveUp: moveSelection(by: -1),
                onMoveDown: moveSelection(by: 1),
                onCommit: commitSelection,
                onCancel: { isShowing = false }
            ))
        }
        .frame(width: 420, height: heightForRows(allCommands.count))
        .background(
            VisualEffectBackground(material: .popover, blendingMode: .withinWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
    }

    private func heightForRows(_ count: Int) -> CGFloat {
        // Each row ~52pt + a 12pt vertical chrome budget. Capped so a future
        // command list bigger than the popup still scrolls.
        min(CGFloat(count) * 52 + 12, 380)
    }

    private var allCommands: [PaletteCommand] {
        let currentURL = editor.currentNote?.url
        let isPinned = currentURL.map(store.isPinned) ?? false
        return [
            PaletteCommand(
                id: "new",
                title: "New note",
                subtitle: "Start a fresh blank draft",
                icon: "square.and.pencil",
                shortcut: "⌘N",
                isEnabled: true
            ) { newNote() },
            PaletteCommand(
                id: "browse",
                title: "Browse notes",
                subtitle: "Open the note switcher",
                icon: "magnifyingglass",
                shortcut: "⌘P",
                isEnabled: true
            ) {
                isShowing = false
                onShowSwitcher()
            },
            PaletteCommand(
                id: "duplicate",
                title: "Duplicate note",
                subtitle: currentURL == nil ? "No note open" : "Copy this note as a new file",
                icon: "doc.on.doc",
                shortcut: nil,
                isEnabled: currentURL != nil
            ) { duplicateCurrent() },
            PaletteCommand(
                id: "pin",
                title: isPinned ? "Unpin note" : "Pin note",
                subtitle: currentURL == nil
                    ? "No note open"
                    : isPinned ? "Remove from top of switcher" : "Float to top of switcher",
                icon: isPinned ? "pin.slash" : "pin",
                shortcut: nil,
                isEnabled: currentURL != nil
            ) { togglePinCurrent() },
            PaletteCommand(
                id: "delete",
                title: "Delete note",
                subtitle: currentURL == nil ? "No note open" : "Move file to trash",
                icon: "trash",
                shortcut: nil,
                isEnabled: currentURL != nil,
                isDestructive: true
            ) { deleteCurrent() },
            PaletteCommand(
                id: "preferences",
                title: "Open Preferences",
                subtitle: "Vault, theme, font size, hotkey",
                icon: "gear",
                shortcut: "⌘,",
                isEnabled: true
            ) {
                isShowing = false
                onShowPreferences()
            }
        ]
    }

    private func moveSelection(by delta: Int) -> () -> Void {
        {
            let last = allCommands.count - 1
            guard last >= 0 else { return }
            // Skip over disabled rows so arrow nav lands on actionable items.
            var next = selectedIndex + delta
            while next >= 0 && next <= last && !allCommands[next].isEnabled {
                next += delta
            }
            if next < 0 || next > last { return }
            selectedIndex = next
        }
    }

    private func commitSelection() {
        guard selectedIndex < allCommands.count else {
            isShowing = false
            return
        }
        let command = allCommands[selectedIndex]
        guard command.isEnabled else { return }
        command.action()
    }

    // MARK: - Actions

    private func newNote() {
        editor.startBlankDraft()
        isShowing = false
    }

    private func duplicateCurrent() {
        guard let url = editor.currentNote?.url else { return }
        do {
            let copy = try store.duplicate(url)
            editor.open(copy)
        } catch {
            NSLog("[Noter] duplicate failed: \(error)")
        }
        isShowing = false
    }

    private func togglePinCurrent() {
        guard let url = editor.currentNote?.url else { return }
        store.togglePin(url)
        isShowing = false
    }

    private func deleteCurrent() {
        guard let url = editor.currentNote?.url else { return }
        do {
            try store.delete(url)
        } catch {
            NSLog("[Noter] delete failed: \(error)")
            return
        }
        if let next = store.notes.first {
            editor.open(next)
        } else {
            editor.startBlankDraft()
        }
        isShowing = false
    }
}

struct PaletteCommand: Identifiable {
    /// String id derived from the action token so the same command keeps the
    /// same identity across re-renders. Don't use `UUID()` — that generates
    /// new ids each time the view rebuilds, which makes `ForEach` treat every
    /// row as new, defeats SwiftUI's diffing, and causes the embedded
    /// SearchField to lose focus on every state change.
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let shortcut: String?
    let isEnabled: Bool
    var isDestructive: Bool = false
    let action: () -> Void
}

private struct CommandRow: View {
    let command: PaletteCommand
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: command.icon)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 22, height: 22)
                .foregroundStyle(iconStyle)
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(titleStyle)
                    .lineLimit(1)
                Text(command.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        .opacity(command.isEnabled ? 1.0 : 0.5)
    }

    private var iconStyle: AnyShapeStyle {
        if !command.isEnabled { return AnyShapeStyle(HierarchicalShapeStyle.tertiary) }
        if command.isDestructive { return AnyShapeStyle(Color.red) }
        return AnyShapeStyle(HierarchicalShapeStyle.primary)
    }

    private var titleStyle: AnyShapeStyle {
        if command.isDestructive {
            return AnyShapeStyle(Color.red)
        }
        return AnyShapeStyle(HierarchicalShapeStyle.primary)
    }
}
