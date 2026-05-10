import AppKit
import Combine
import SwiftUI
import WebKit

/// Bridges the SwiftUI world to a WKWebView hosting CodeMirror. Loads the
/// bundled `editor.html`, hooks up the message bridge, and keeps SwiftUI's
/// `text` binding in sync with the editor's document.
struct EditorWebView: NSViewRepresentable {
    @Binding var text: String
    var configuration: EditorConfiguration
    var onCommandsReady: ((MarkdownCommands) -> Void)?
    var onOpenURL: ((String) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let webConfig = WKWebViewConfiguration()
        webConfig.preferences.javaScriptCanOpenWindowsAutomatically = false
        webConfig.defaultWebpagePreferences.allowsContentJavaScript = true
        if #available(macOS 13.3, *) {
            webConfig.preferences.isElementFullscreenEnabled = false
        }

        let webView = TransparentWebView(frame: .zero, configuration: webConfig)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.setValue(false, forKey: "drawsBackground")

        context.coordinator.attach(to: webView)
        loadBundledEditor(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(text: text, configuration: configuration)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            configuration: configuration,
            onCommandsReady: onCommandsReady,
            onOpenURL: onOpenURL
        )
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.detach()
        webView.stopLoading()
    }

    // MARK: - Loading

    private func loadBundledEditor(into webView: WKWebView) {
        guard let htmlURL = Bundle.module.url(forResource: "editor", withExtension: "html") else {
            NSLog("[MarkdownEditor] editor.html missing from bundle")
            return
        }
        let baseURL = htmlURL.deletingLastPathComponent()
        webView.loadFileURL(htmlURL, allowingReadAccessTo: baseURL)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {
        private let bridge = EditorBridge()
        private let commands = MarkdownCommands()
        private var linkPopover: LinkPopoverController?
        private var lastSentConfig: EditorConfiguration?
        private var lastSentText: String?
        private var didNotifyReady = false
        private var textBinding: Binding<String>
        private var configuration: EditorConfiguration
        private var onCommandsReady: ((MarkdownCommands) -> Void)?
        private var onOpenURL: ((String) -> Void)?

        init(
            text: Binding<String>,
            configuration: EditorConfiguration,
            onCommandsReady: ((MarkdownCommands) -> Void)?,
            onOpenURL: ((String) -> Void)?
        ) {
            textBinding = text
            self.configuration = configuration
            self.onCommandsReady = onCommandsReady
            self.onOpenURL = onOpenURL
            super.init()
            commands.bridge = bridge
            bridge.onReady = { [weak self] in self?.handleReady() }
            bridge.onTextChanged = { [weak self] text in self?.handleTextChanged(text) }
            bridge.onSelectionChanged = { [weak self] styles in
                self?.handleSelectionChanged(styles)
            }
            bridge.onOpenURL = { [weak self] url in self?.onOpenURL?(url) }
            bridge.onLinkInspect = { [weak self] payload in
                self?.linkPopover?.presentInspect(payload: payload)
            }
            bridge.onLinkCreateRequest = { [weak self] payload in
                self?.linkPopover?.presentEdit(
                    initialURL: "",
                    range: payload.from ... payload.to,
                    rect: payload.rect,
                    mode: .createNew
                )
            }
            bridge.onLog = { level, message in
                NSLog("[MarkdownEditor JS][\(level)] \(message)")
            }
        }

        func attach(to webView: WKWebView) {
            bridge.attach(to: webView)
            linkPopover = LinkPopoverController(webView: webView, bridge: bridge)
        }

        func detach() {
            bridge.detach()
        }

        /// Called from `updateNSView` whenever SwiftUI re-evaluates the view.
        func update(text: String, configuration: EditorConfiguration) {
            if configuration != self.configuration {
                self.configuration = configuration
            }
            pushConfigIfNeeded()
            pushTextIfNeeded(text)
        }

        func updateBinding(_ binding: Binding<String>) {
            textBinding = binding
        }

        // MARK: Inbound

        private func handleReady() {
            pushConfigIfNeeded(force: true)
            pushTextIfNeeded(textBinding.wrappedValue, force: true)
            if !didNotifyReady {
                didNotifyReady = true
                onCommandsReady?(commands)
            }
        }

        private func handleTextChanged(_ text: String) {
            // Avoid the round-trip echo: only update the binding when the
            // editor's text differs from what we last pushed.
            if text == lastSentText { return }
            lastSentText = text
            textBinding.wrappedValue = text
        }

        private func handleSelectionChanged(_ styles: Set<MarkdownStyle>) {
            commands.activeStyles = styles
        }

        // MARK: Outbound

        private func pushConfigIfNeeded(force: Bool = false) {
            if !force, lastSentConfig == configuration { return }
            lastSentConfig = configuration
            bridge.send(.applyConfig(configuration))
        }

        private func pushTextIfNeeded(_ text: String, force: Bool = false) {
            if !force, lastSentText == text { return }
            lastSentText = text
            bridge.send(.setText(text))
        }
    }
}

/// A WKWebView that draws nothing in its own background so the parent
/// SwiftUI/AppKit blur material shows through.
private final class TransparentWebView: WKWebView {
    override var isOpaque: Bool {
        false
    }
}
