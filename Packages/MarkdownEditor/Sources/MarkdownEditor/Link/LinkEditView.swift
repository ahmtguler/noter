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
                // .roundedBorder draws a heavy 3pt focus ring that drowns
                // out the popover's chrome; .plain + a custom 1pt border
                // matches the rest of the app's restraint.
                .textFieldStyle(.plain)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(
                            fieldFocused
                                ? Color.accentColor.opacity(0.55)
                                : Color.primary.opacity(0.18),
                            lineWidth: 1
                        )
                )
                .frame(maxWidth: .infinity)
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
        .padding(.vertical, 6)
        .onAppear { fieldFocused = true }
    }
}
