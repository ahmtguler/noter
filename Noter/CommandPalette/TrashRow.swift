import SwiftUI

/// Row inside the ⌘K palette's "Recently Deleted" view. Shows the note's
/// title and how long ago it was trashed, with Restore + Delete-permanently
/// icon buttons on the right.
struct TrashRow: View {
    let note: Note
    let isSelected: Bool
    let onRestore: () -> Void
    let onPurge: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text("Deleted \(RelativeTime.string(from: note.modifiedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            TrashIconButton(
                systemName: "arrow.uturn.backward",
                tooltip: "Restore",
                tint: .accentColor,
                action: onRestore
            )
            TrashIconButton(
                systemName: "trash",
                tooltip: "Delete permanently",
                tint: .red,
                action: onPurge
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
    }
}

private struct TrashIconButton: View {
    let systemName: String
    let tooltip: String
    let tint: Color
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
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
