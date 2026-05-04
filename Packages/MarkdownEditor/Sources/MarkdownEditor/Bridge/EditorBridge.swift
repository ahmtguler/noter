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

    func send(_ message: OutboundMessage) {
        guard isReady, let webView else {
            pendingOutbound.append(message)
            return
        }
        evaluate(message.javascript(), on: webView)
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
