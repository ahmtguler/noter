import SwiftUI

/// Hover popover for an existing link. Shows the URL and offers Copy / Edit.
/// (Open is not in this UI — plain click on the link in the editor already
/// opens it via NSWorkspace.)
struct LinkInspectView: View {
    let url: String
    let onCopy: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(url)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 260, alignment: .leading)
            IconButton(systemName: "doc.on.doc", tooltip: "Copy", action: onCopy)
            IconButton(systemName: "pencil", tooltip: "Edit", action: onEdit)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 220)
    }
}
