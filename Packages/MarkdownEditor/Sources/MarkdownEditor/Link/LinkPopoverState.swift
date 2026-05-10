import Foundation

/// State driving the in-editor link popover. Lives at `MarkdownEditor`'s
/// `@StateObject` level; the EditorWebView coordinator pushes payloads in
/// here and the LinkPopoverOverlay reads them to render. Replaces the prior
/// NSPopover host so the popover stays inside the editor view's bounds
/// instead of escaping into a free-floating native popover window.
@MainActor
final class LinkPopoverState: ObservableObject {
    enum Mode: Equatable {
        case inspect(url: String)
        case edit(initialURL: String, kind: EditKind)
    }

    enum EditKind: Equatable {
        /// Trash button removes the existing markdown link from the doc.
        case editExisting
        /// Trash button just dismisses — there's nothing to remove yet.
        case createNew
    }

    struct Active: Equatable {
        let mode: Mode
        let range: ClosedRange<Int>
        let rect: ViewportRect
    }

    @Published var active: Active?

    /// Dispatched by the overlay's edit form on Confirm. Coordinator wires
    /// it to a `linkApply` bridge command.
    var onApplyLink: ((Int, Int, String) -> Void)?
    /// Dispatched by the overlay's trash icon when in `editExisting` mode.
    /// Coordinator wires it to a `linkRemove` bridge command.
    var onRemoveLink: ((Int, Int) -> Void)?

    func presentInspect(_ payload: LinkInspectPayload) {
        active = Active(
            mode: .inspect(url: payload.url),
            range: payload.from ... payload.to,
            rect: payload.rect
        )
    }

    func presentEdit(
        initialURL: String,
        range: ClosedRange<Int>,
        rect: ViewportRect,
        kind: EditKind
    ) {
        active = Active(
            mode: .edit(initialURL: initialURL, kind: kind),
            range: range,
            rect: rect
        )
    }

    func close() {
        active = nil
    }
}
