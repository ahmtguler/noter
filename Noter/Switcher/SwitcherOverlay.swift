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
                                isCurrent: item.note.url == editor.currentNote?.url
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
                .onChange(of: selectedIndex) { _, new in
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
        .frame(width: 420, height: 360)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
        .onChange(of: query) { _, _ in selectedIndex = 0 }
    }

    private var matches: [(note: Note, score: Int)] {
        if query.isEmpty {
            return store.notes
                .sorted { recencyKey($0) > recencyKey($1) }
                .map { ($0, 0) }
        }

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return store.notes
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
                    Text(note.modifiedAt, style: .relative)
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear)
    }
}
