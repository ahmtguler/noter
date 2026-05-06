import SwiftUI

/// ⌘P note switcher. Floats over the editor, lets the user fuzzy-search notes by
/// title and full-text-search note bodies, navigate with arrows, open with Enter.
struct SwitcherOverlay: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var editor: EditorState
    @Binding var isShowing: Bool

    @State private var query = ""
    @State private var selectedIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            SearchField(
                text: $query,
                onMoveUp: moveSelection(by: -1),
                onMoveDown: moveSelection(by: 1),
                onCommit: commitSelection,
                onCancel: { isShowing = false }
            )
            .padding(.horizontal, 14)
            .frame(height: 38)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(matches.enumerated()), id: \.element.note.id) { index, item in
                            SwitcherRow(
                                note: item.note,
                                isSelected: index == selectedIndex,
                                isCurrent: item.note.url == editor.currentNote?.url,
                                isPinned: store.isPinned(item.note.url),
                                onPin: { store.togglePin(item.note.url) },
                                onDelete: { deleteNote(item.note) }
                            )
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedIndex = index
                                commitSelection()
                            }
                        }
                    }
                }
                .background(ArrowCursorArea())
                .onChange(of: selectedIndex) { _, new in
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
        .frame(width: 420, height: 360)
        .background(
            VisualEffectBackground(material: .popover, blendingMode: .withinWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
        .onChange(of: query) { _, _ in selectedIndex = 0 }
    }

    private var matches: [(note: Note, score: Int)] {
        let raw: [(Note, Int)]
        if query.isEmpty {
            raw = store.notes
                .sorted { recencyKey($0) > recencyKey($1) }
                .map { ($0, 0) }
        } else {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            raw = store.notes
                .compactMap { note -> (Note, Int)? in
                    if let titleScore = FuzzyMatcher.score(query: trimmed, in: note.title) {
                        return (note, titleScore + 1000)
                    }
                    if note.body.localizedCaseInsensitiveContains(trimmed) {
                        return (note, 100)
                    }
                    return nil
                }
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                    return recencyKey(lhs.0) > recencyKey(rhs.0)
                }
        }
        // Pinned notes float to the top, preserving the relative ordering
        // produced above within each group.
        let pinned = raw.filter { store.isPinned($0.0.url) }
        let rest = raw.filter { !store.isPinned($0.0.url) }
        return pinned + rest
    }

    private func deleteNote(_ note: Note) {
        let isOpen = editor.currentNote?.url == note.url
        do {
            try store.delete(note.url)
        } catch {
            NSLog("[Noter] delete failed: \(error)")
            return
        }
        if isOpen {
            if let next = store.notes.first {
                editor.open(next)
            } else {
                editor.startBlankDraft()
            }
        }
        if selectedIndex >= matches.count {
            selectedIndex = max(0, matches.count - 1)
        }
    }

    private func recencyKey(_ note: Note) -> Date {
        note.openedAt ?? note.modifiedAt
    }

    private func moveSelection(by delta: Int) -> () -> Void {
        {
            let lastIndex = matches.count - 1
            guard lastIndex >= 0 else { return }
            selectedIndex = max(0, min(lastIndex, selectedIndex + delta))
        }
    }

    private func commitSelection() {
        guard selectedIndex < matches.count else {
            isShowing = false
            return
        }
        let note = matches[selectedIndex].note
        editor.open(note)
        isShowing = false
    }
}

struct SwitcherRow: View {
    let note: Note
    let isSelected: Bool
    let isCurrent: Bool
    let isPinned: Bool
    let onPin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(note.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if isCurrent {
                        Text("Current")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    Text(RelativeTime.string(from: note.modifiedAt))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("·")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("\(note.characterCount.formatted()) characters")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            Spacer()
            RowIconButton(
                systemName: isPinned ? "pin.fill" : "pin",
                tooltip: isPinned ? "Unpin" : "Pin",
                tint: isPinned ? .accentColor : nil,
                action: onPin
            )
            RowIconButton(
                systemName: "trash",
                tooltip: "Delete",
                tint: nil,
                action: onDelete
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear)
    }
}

/// Hover/press-aware icon button with a tooltip. SwiftUI's `.help()` on
/// borderless buttons is unreliable in macOS 26 popups, so we apply the
/// tooltip to the underlying NSView and render hover/press feedback
/// ourselves with a tinted background.
private struct RowIconButton: View {
    let systemName: String
    let tooltip: String
    let tint: Color?
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint.map { AnyShapeStyle($0) }
                ?? AnyShapeStyle(HierarchicalShapeStyle.secondary))
            .frame(width: 24, height: 24)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in
                        if isPressed { action() }
                        isPressed = false
                    }
            )
            .background(NativeTooltip(text: tooltip))
    }

    private var background: Color {
        if isPressed { return Color.primary.opacity(0.15) }
        if isHovering { return Color.primary.opacity(0.08) }
        return .clear
    }
}

/// Bridges into AppKit just to get a reliable native tooltip. SwiftUI's
/// `.help()` doesn't surface on borderless rows here.
private struct NativeTooltip: NSViewRepresentable {
    let text: String

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        nsView.toolTip = text
    }
}
