import AppKit
import SwiftUI

/// ⌘K command palette. Two modes: a flat list of actions, and a
/// "Recently Deleted" list with per-row Restore / Delete-permanently
/// buttons. Mode is local state — switching back is "← Back" or Esc.
struct CommandPaletteOverlay: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var editor: EditorState
    @Binding var isShowing: Bool
    var onShowSwitcher: () -> Void
    var onShowPreferences: () -> Void

    @State private var mode: Mode = .commands
    @State private var selectedIndex = 0
    /// Cached snapshot of the trashed notes for the trash mode. Populated on
    /// `enter(.trash)` and refreshed on each Restore / Delete action so the
    /// list stays in sync without polling.
    @State private var trashedSnapshot: [Note] = []

    enum Mode: Equatable {
        case commands
        case trash
    }

    var body: some View {
        VStack(spacing: 0) {
            if mode == .trash {
                trashHeader
                Divider().opacity(0.4)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        switch mode {
                        case .commands:
                            ForEach(Array(allCommands.enumerated()), id: \.element.id) { index, command in
                                Button {
                                    selectedIndex = index
                                    commitSelection()
                                } label: {
                                    CommandRow(
                                        command: command,
                                        isSelected: index == selectedIndex
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(command.id)
                            }
                        case .trash:
                            if trashedSnapshot.isEmpty {
                                emptyTrashState
                            } else {
                                ForEach(Array(trashedSnapshot.enumerated()), id: \.element.id) { index, note in
                                    Button {
                                        selectedIndex = index
                                    } label: {
                                        TrashRow(
                                            note: note,
                                            isSelected: index == selectedIndex,
                                            onRestore: { restore(note) },
                                            onPurge: { permanentlyDelete(note) }
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .id(note.id)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onChange(of: selectedIndex) { _, new in
                    switch mode {
                    case .commands:
                        if new < allCommands.count {
                            proxy.scrollTo(allCommands[new].id, anchor: .center)
                        }
                    case .trash:
                        if new < trashedSnapshot.count {
                            proxy.scrollTo(trashedSnapshot[new].id, anchor: .center)
                        }
                    }
                }
            }
            .background(KeyCatcher(
                onMoveUp: moveSelection(by: -1),
                onMoveDown: moveSelection(by: 1),
                onCommit: commitSelection,
                onCancel: cancelOrBack
            ))
        }
        .frame(width: 380, height: contentHeight)
        // Arrow-cursor rect on the outer frame so the I-beam from any inner
        // text-input doesn't leak past its own bounds. Scoped narrower
        // (.background on the ScrollView only) didn't work — SwiftUI's
        // hosting layout absorbed the rect lookup before AppKit got it.
        .background(ArrowCursorArea())
        .background(
            // hudWindow is a more aggressive blur with stronger transparency
            // than .popover — the palette feels "floaty" rather than solid.
            VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
    }

    private var contentHeight: CGFloat {
        // Per-row size includes inner vpad (16) + outer chip pad (2) + content
        // (~31). Adds the LazyVStack's own vertical padding as the chrome term.
        let rowHeight: CGFloat = 49
        let listChrome: CGFloat = 12
        switch mode {
        case .commands:
            return min(CGFloat(allCommands.count) * rowHeight + listChrome, 380)
        case .trash:
            // Trash mode also has the back/header bar (~44) + a divider (1pt).
            let trashChrome: CGFloat = listChrome + 45
            if trashedSnapshot.isEmpty { return trashChrome + 130 }
            return min(CGFloat(trashedSnapshot.count) * rowHeight + trashChrome, 420)
        }
    }

    private var trashHeader: some View {
        HStack(spacing: 10) {
            Button(action: backToCommands) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back (Esc)")
            VStack(alignment: .leading, spacing: 1) {
                Text("Recently Deleted")
                    .font(.body.weight(.medium))
                Text(trashHeaderSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var trashHeaderSubtitle: String {
        if trashedSnapshot.isEmpty { return "Empty" }
        let plural = trashedSnapshot.count == 1 ? "" : "s"
        return "\(trashedSnapshot.count) note\(plural) · auto-removed after 14 days"
    }

    private var emptyTrashState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Nothing in Recently Deleted")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - Commands

    private var allCommands: [PaletteCommand] {
        let currentURL = editor.currentNote?.url
        let isPinned = currentURL.map(store.isPinned) ?? false
        let trashCount = store.trashedNotes().count
        return [
            PaletteCommand(
                id: "new",
                title: "New note",
                subtitle: "Start a fresh blank draft",
                icon: "square.and.pencil",
                shortcut: "⌘ N",
                isEnabled: true
            ) { newNote() },
            PaletteCommand(
                id: "browse",
                title: "Browse notes",
                subtitle: "Open the note switcher",
                icon: "magnifyingglass",
                shortcut: "⌘ P",
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
                subtitle: currentURL == nil ? "No note open" : "Move to Recently Deleted",
                icon: "trash",
                shortcut: nil,
                isEnabled: currentURL != nil,
                isDestructive: true
            ) { deleteCurrent() },
            PaletteCommand(
                id: "trash",
                title: "Recently Deleted",
                subtitle: trashCount == 0
                    ? "Empty"
                    : "\(trashCount) note\(trashCount == 1 ? "" : "s") · restore or remove",
                icon: "tray",
                shortcut: nil,
                isEnabled: true
            ) { enter(.trash) },
            PaletteCommand(
                id: "preferences",
                title: "Open Preferences",
                subtitle: "Vault, theme, font size, hotkey",
                icon: "gear",
                shortcut: "⌘ ,",
                isEnabled: true
            ) {
                isShowing = false
                onShowPreferences()
            }
        ]
    }

    private func moveSelection(by delta: Int) -> () -> Void {
        {
            let last = currentRowCount - 1
            guard last >= 0 else { return }
            var next = selectedIndex + delta
            if mode == .commands {
                while next >= 0, next <= last, !allCommands[next].isEnabled {
                    next += delta
                }
            }
            if next < 0 || next > last { return }
            selectedIndex = next
        }
    }

    private var currentRowCount: Int {
        switch mode {
        case .commands: allCommands.count
        case .trash: trashedSnapshot.count
        }
    }

    private func commitSelection() {
        switch mode {
        case .commands:
            guard selectedIndex < allCommands.count else {
                isShowing = false
                return
            }
            let command = allCommands[selectedIndex]
            guard command.isEnabled else { return }
            command.action()
        case .trash:
            guard selectedIndex < trashedSnapshot.count else { return }
            restore(trashedSnapshot[selectedIndex])
        }
    }

    private func cancelOrBack() {
        if mode == .trash {
            backToCommands()
        } else {
            isShowing = false
        }
    }

    private func enter(_ next: Mode) {
        if next == .trash {
            trashedSnapshot = store.trashedNotes()
        }
        selectedIndex = 0
        mode = next
    }

    private func backToCommands() {
        mode = .commands
        selectedIndex = 0
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

    private func restore(_ note: Note) {
        do {
            let restored = try store.restoreTrashed(note.url)
            editor.open(restored)
        } catch {
            NSLog("[Noter] restore failed: \(error)")
            return
        }
        trashedSnapshot = store.trashedNotes()
        clampSelection()
        isShowing = false
    }

    private func permanentlyDelete(_ note: Note) {
        do {
            try store.permanentlyDeleteTrashed(note.url)
        } catch {
            NSLog("[Noter] purge failed: \(error)")
            return
        }
        trashedSnapshot = store.trashedNotes()
        clampSelection()
    }

    private func clampSelection() {
        let last = max(0, trashedSnapshot.count - 1)
        if selectedIndex > last { selectedIndex = last }
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
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
