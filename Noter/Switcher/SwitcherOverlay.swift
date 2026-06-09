import AppKit
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
                            Button {
                                selectedIndex = index
                                commitSelection()
                            } label: {
                                SwitcherRow(
                                    note: item.note,
                                    isSelected: index == selectedIndex,
                                    isCurrent: item.note.url == editor.currentNote?.url,
                                    isPinned: store.isPinned(item.note.url),
                                    onPin: { store.togglePin(item.note.url) },
                                    onDelete: { deleteNote(item.note) }
                                )
                            }
                            .buttonStyle(.plain)
                            // Use the note's URL as the scroll-target id —
                            // stable across reorders. .id(index) was tearing
                            // down rows on each pin toggle and the row state
                            // change wasn't visible until reopen.
                            .id(item.note.id)
                        }
                    }
                }
                .onChange(of: selectedIndex) { _, new in
                    if new < matches.count {
                        proxy.scrollTo(matches[new].note.id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 380, height: 360)
        // Arrow-cursor rect on the outer frame so it covers the row area;
        // SearchField still owns its own I-beam rect inside its bounds.
        .background(ArrowCursorArea())
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
        .onChange(of: query) { _, _ in selectedIndex = 0 }
        // Every mouseMoved that lands on the panel: schedule arrow set on
        // the NEXT run-loop tick. WebKit's WKContentView sets its I-beam
        // synchronously inside the same mouseMoved dispatch — by deferring
        // ours with `async`, we land *after* WebKit and the arrow wins.
        // Events still pass through, so row .onHover keeps working.
        .onContinuousHover { phase in
            if case .active = phase {
                DispatchQueue.main.async { NSCursor.arrow.set() }
            }
        }
        // ⇧⌘⌫ deletes the highlighted row. PanelKeyMonitor intercepts the
        // chord before SearchField sees it, so it arrives as a notification.
        .onReceive(NotificationCenter.default.publisher(for: .noterDeleteActiveNote)) { _ in
            guard selectedIndex < matches.count else { return }
            deleteNote(matches[selectedIndex].note)
        }
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

    @State private var isHovering = false

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
            Spacer(minLength: 0)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(rowBackground)
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        // contentShape AFTER the outer padding so the whole row rect
        // (including the spacer between the title and the icons) is
        // hit-testable for the wrapping Button. Without this, the Spacer
        // region wasn't registering clicks.
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.22) }
        if isHovering { return Color.primary.opacity(0.08) }
        return .clear
    }
}

/// Hover-aware icon button with a tooltip. Wrapped in a SwiftUI Button so
/// the click is consumed and doesn't bubble up to the row's button —
/// without this the row's commit-selection handler ran in the same tick,
/// closing the switcher before the user could see the pin/delete take
/// effect.
private struct RowIconButton: View {
    let systemName: String
    let tooltip: String
    let tint: Color?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint.map { AnyShapeStyle($0) }
                    ?? AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .frame(width: 26, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        // Stronger fill than the row's hover tint so the
                        // icon's hit-target is distinguishable when the row
                        // itself is also highlighted underneath.
                        .fill(isHovering ? Color.primary.opacity(0.18) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .background(NativeTooltip(text: tooltip))
    }
}
