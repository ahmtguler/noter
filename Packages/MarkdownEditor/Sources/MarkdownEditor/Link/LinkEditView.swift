import SwiftUI

/// URL editor used both for creating a fresh link from a selection and for
/// editing an existing one. The trash icon either removes the existing
/// link (edit mode) or cancels the create flow without inserting anything.
struct LinkEditView: View {
    let initialURL: String
    let onCommit: (String) -> Void
    let onTrash: () -> Void

    @State private var url: String
    @FocusState private var fieldFocused: Bool

    init(
        initialURL: String,
        onCommit: @escaping (String) -> Void,
        onTrash: @escaping () -> Void
    ) {
        self.initialURL = initialURL
        self.onCommit = onCommit
        self.onTrash = onTrash
        _url = State(initialValue: initialURL)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("https://", text: $url)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .focused($fieldFocused)
                .onSubmit { onCommit(url) }
            IconButton(systemName: "checkmark", tooltip: "Confirm", action: { onCommit(url) })
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            IconButton(
                systemName: "trash",
                tooltip: "Remove link",
                tint: .red,
                action: onTrash
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 320)
        .onAppear { fieldFocused = true }
    }
}
