import AppKit
import SwiftUI
import WebKit

/// Owns the link popovers anchored to the editor — both the "inspect"
/// hover popover (Copy / Edit) and the "edit" form (URL field + OK + Trash).
/// Single NSPopover that swaps its content view between the two states; the
/// anchor rect persists across the swap so the popover stays put.
@MainActor
final class LinkPopoverController {
    private weak var webView: WKWebView?
    private weak var bridge: EditorBridge?
    private let popover: NSPopover
    /// Range the active popover refers to. For inspect mode it's the link's
    /// full doc range; for edit mode it's the same (or, in create mode, the
    /// selection range that's about to become a link).
    private var activeRange: ClosedRange<Int>?
    private var lastAnchorRect: NSRect = .zero
    /// Differentiates "create new link" from "edit existing link" so the
    /// trash button knows whether to remove the link or just dismiss.
    private var editMode: EditMode = .editExisting

    enum EditMode {
        case editExisting
        case createNew
    }

    init(webView: WKWebView, bridge: EditorBridge) {
        self.webView = webView
        self.bridge = bridge
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
    }

    /// Hover popover. Shows the URL with Copy + Edit buttons.
    func presentInspect(payload: LinkInspectPayload) {
        guard let webView else { return }
        activeRange = payload.from ... payload.to
        lastAnchorRect = anchorRect(from: payload.rect, in: webView)
        let view = LinkInspectView(
            url: payload.url,
            onCopy: { [weak self] in self?.handleCopy(url: payload.url) },
            onEdit: { [weak self] in
                self?.presentEdit(
                    initialURL: payload.url,
                    range: payload.from ... payload.to,
                    rect: payload.rect,
                    mode: .editExisting
                )
            }
        )
        showHosted(view: AnyView(view), in: webView)
    }

    /// Edit / create form: URL TextField, OK to apply, trash to either remove
    /// the existing link (`editExisting`) or cancel (`createNew`).
    func presentEdit(
        initialURL: String,
        range: ClosedRange<Int>,
        rect: ViewportRect,
        mode: EditMode
    ) {
        guard let webView else { return }
        activeRange = range
        editMode = mode
        lastAnchorRect = anchorRect(from: rect, in: webView)
        let view = LinkEditView(
            initialURL: initialURL,
            onCommit: { [weak self] url in
                guard let self else { return }
                let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                bridge?.send(.execute(
                    command: .linkApply,
                    arg: jsonString(["from": range.lowerBound, "to": range.upperBound, "url": trimmed])
                ))
                close()
            },
            onTrash: { [weak self] in
                guard let self else { return }
                if mode == .editExisting {
                    bridge?.send(.execute(
                        command: .linkRemove,
                        arg: jsonString(["from": range.lowerBound, "to": range.upperBound])
                    ))
                }
                close()
            }
        )
        showHosted(view: AnyView(view), in: webView)
    }

    func close() {
        if popover.isShown { popover.close() }
        activeRange = nil
    }

    // MARK: - Helpers

    private func handleCopy(url: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url, forType: .string)
        close()
    }

    private func showHosted(view: AnyView, in anchorView: NSView) {
        let host = NSHostingController(rootView: view)
        popover.contentViewController = host
        popover.contentSize = host.view.fittingSize
        if popover.isShown {
            // Same popover, swap content. Re-anchor so swap doesn't move the
            // popover (NSPopover repositions on contentSize change).
            popover.positioningRect = lastAnchorRect
        } else {
            popover.show(relativeTo: lastAnchorRect, of: anchorView, preferredEdge: .maxY)
        }
    }

    /// Convert WKWebView-relative coords into the rect API NSPopover expects
    /// (positioning rect in the anchor view's bounds coordinate system).
    /// JS sends viewport coords from `getBoundingClientRect`/`coordsAtPos`,
    /// which align with the WKWebView's content view bounds.
    private func anchorRect(from rect: ViewportRect, in webView: WKWebView) -> NSRect {
        let raw = NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        // WebView bounds and JS viewport coords share the same origin (top-left
        // in flipped views). NSPopover positioning rect uses the anchor view's
        // own coordinate system — webView.bounds — so no further conversion
        // is needed for a flipped or unflipped child view.
        return raw.intersection(NSRect(origin: .zero, size: webView.bounds.size))
    }

    private func jsonString(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8)
        else { return "{}" }
        return string
    }
}
