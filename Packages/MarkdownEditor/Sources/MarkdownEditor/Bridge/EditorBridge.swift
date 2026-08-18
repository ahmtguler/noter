import AppKit
import Combine
import Foundation
import WebKit

/// Owns the message-passing relationship between Swift and the JS editor.
/// Holds a queue of outbound messages until the JS side reports `ready`, then
/// flushes them in order. Inbound messages are dispatched to the relevant
/// observers via the closures the `EditorWebView` installs.
@MainActor
final class EditorBridge: NSObject, WKScriptMessageHandler {
    private weak var webView: WKWebView?
    private var pendingOutbound: [OutboundMessage] = []
    private var isReady = false

    /// Called when the JS side signals it's ready to receive messages.
    var onReady: (() -> Void)?
    /// Called whenever the document text changes inside the editor.
    var onTextChanged: ((String) -> Void)?
    /// Called whenever the caret/selection moves and active styles change.
    var onSelectionChanged: ((Set<MarkdownStyle>) -> Void)?
    /// Surfaces console-style logs from the JS side for debugging.
    var onLog: ((String, String) -> Void)?
    /// Fires when the user clicks a link inside the editor — Swift opens the
    /// URL with `NSWorkspace`. Keeping this on the host (not the JS side) so
    /// the WKWebView never tries to navigate itself.
    var onOpenURL: ((String) -> Void)?
    /// Hover lingered on a link long enough to show the inspect popover.
    var onLinkInspect: ((LinkInspectPayload) -> Void)?
    /// Toolbar Link button pressed with a non-empty selection.
    var onLinkCreateRequest: ((LinkCreatePayload) -> Void)?

    func attach(to webView: WKWebView) {
        self.webView = webView
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        webView.configuration.userContentController.add(self, name: "editor")
    }

    func detach() {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "editor")
        webView = nil
        isReady = false
        pendingOutbound.removeAll()
    }

    /// Drops the ready handshake so outbound messages queue again, without
    /// tearing down the script-message handler the way `detach` does. Used when
    /// the web content process dies and the page is reloaded: the new page has
    /// no CodeMirror until it reports `ready`, and anything evaluated before
    /// then is silently lost.
    func prepareForReload() {
        isReady = false
    }

    func send(_ message: OutboundMessage) {
        guard isReady, let webView else {
            pendingOutbound.append(message)
            return
        }
        evaluate(message.javascript(), on: webView)
    }

    /// Make the web view the window's first responder so keystrokes route into
    /// CodeMirror. Load-bearing when another AppKit view holds first responder
    /// — an overlay's text field, or the window after the popup re-shows. A
    /// JS-only `view.focus()` can't reclaim key events in those cases. Skips
    /// the call when focus already lives inside the web view to avoid flicker.
    func makeWebViewFirstResponder() {
        guard let webView, let window = webView.window else { return }
        if let responder = window.firstResponder as? NSView, responder.isDescendant(of: webView) {
            return
        }
        window.makeFirstResponder(webView)
    }

    // MARK: - WKScriptMessageHandler

    nonisolated func userContentController(
        _: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard message.name == "editor" else { return }
            handle(body: message.body)
        }
    }

    // MARK: - Internal

    private func handle(body: Any) {
        do {
            let data: Data = if let string = body as? String, let encoded = string.data(using: .utf8) {
                encoded
            } else {
                try JSONSerialization.data(withJSONObject: body)
            }
            let inbound = try JSONDecoder().decode(InboundMessage.self, from: data)
            switch inbound {
            case .ready:
                isReady = true
                let queued = pendingOutbound
                pendingOutbound.removeAll()
                if let webView {
                    for message in queued {
                        evaluate(message.javascript(), on: webView)
                    }
                }
                onReady?()
            case let .textChanged(text):
                onTextChanged?(text)
            case let .selectionChanged(styles):
                onSelectionChanged?(styles)
            case let .logging(level, message):
                onLog?(level, message)
            case let .openURL(url):
                onOpenURL?(url)
            case let .linkInspect(payload):
                onLinkInspect?(payload)
            case let .linkCreateRequest(payload):
                onLinkCreateRequest?(payload)
            }
        } catch {
            NSLog("[MarkdownEditor] failed to decode bridge message: \(error)")
        }
    }

    private func evaluate(_ script: String, on webView: WKWebView) {
        webView.evaluateJavaScript(script) { _, error in
            if let error {
                NSLog("[MarkdownEditor] evaluateJavaScript failed: \(error)")
            }
        }
    }
}
