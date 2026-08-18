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
    var linkState: LinkPopoverState

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
        // SwiftUI builds the coordinator once but re-creates this struct on
        // every update, so a coordinator holding its original binding and
        // callbacks would keep writing keystrokes into whichever `Binding` and
        // closures existed at creation. Harmless while the host keeps handing
        // over the same ones; silent data loss the moment it doesn't.
        context.coordinator.rebind(
            text: $text,
            onCommandsReady: onCommandsReady,
            onOpenURL: onOpenURL
        )
        context.coordinator.update(text: text, configuration: configuration)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            configuration: configuration,
            onCommandsReady: onCommandsReady,
            onOpenURL: onOpenURL,
            linkState: linkState
        )
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.detach()
        webView.stopLoading()
    }

    // MARK: - Loading

    /// Static so the coordinator can reload after a content-process crash.
    fileprivate static func loadBundledEditor(into webView: WKWebView) {
        guard let htmlURL = Bundle.module.url(forResource: "editor", withExtension: "html") else {
            NSLog("[MarkdownEditor] editor.html missing from bundle")
            return
        }
        let baseURL = htmlURL.deletingLastPathComponent()
        webView.loadFileURL(htmlURL, allowingReadAccessTo: baseURL)
    }

    private func loadBundledEditor(into webView: WKWebView) {
        Self.loadBundledEditor(into: webView)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {
        private let bridge = EditorBridge()
        private let commands = MarkdownCommands()
        private let linkState: LinkPopoverState
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
            onOpenURL: ((String) -> Void)?,
            linkState: LinkPopoverState
        ) {
            textBinding = text
            self.configuration = configuration
            self.onCommandsReady = onCommandsReady
            self.onOpenURL = onOpenURL
            self.linkState = linkState
            super.init()
            commands.bridge = bridge
            linkState.onApplyLink = { [weak bridge] from, to, url in
                let arg = #"{"from":\#(from),"to":\#(to),"url":\#(jsonEscape(url))}"#
                bridge?.send(.execute(command: .linkApply, arg: arg))
            }
            linkState.onRemoveLink = { [weak bridge] from, to in
                let arg = #"{"from":\#(from),"to":\#(to)}"#
                bridge?.send(.execute(command: .linkRemove, arg: arg))
            }
            bridge.onReady = { [weak self] in self?.handleReady() }
            bridge.onTextChanged = { [weak self] text in self?.handleTextChanged(text) }
            bridge.onSelectionChanged = { [weak self] styles in
                self?.handleSelectionChanged(styles)
            }
            bridge.onOpenURL = { [weak self] url in self?.handleOpenURL(url) }
            bridge.onLinkInspect = { [weak self] payload in
                self?.linkState.presentInspect(payload)
            }
            bridge.onLinkCreateRequest = { [weak self] payload in
                self?.linkState.presentEdit(
                    initialURL: "",
                    range: payload.from ... payload.to,
                    rect: payload.rect,
                    kind: .createNew
                )
            }
            bridge.onLog = { level, message in
                NSLog("[MarkdownEditor JS][\(level)] \(message)")
            }
        }

        func attach(to webView: WKWebView) {
            webView.navigationDelegate = self
            bridge.attach(to: webView)
        }

        func detach() {
            bridge.detach()
        }

        /// Clears the handshake and the "already sent" bookkeeping so the page
        /// that comes back after a reload is re-populated from scratch.
        func prepareForReload() {
            bridge.prepareForReload()
            lastSentText = nil
            lastSentConfig = nil
        }

        /// Called from `updateNSView` whenever SwiftUI re-evaluates the view.
        func update(text: String, configuration: EditorConfiguration) {
            if configuration != self.configuration {
                self.configuration = configuration
            }
            pushConfigIfNeeded()
            pushTextIfNeeded(text)
        }

        /// Re-points at the current binding and callbacks. Called from
        /// `updateNSView`; see the note there.
        func rebind(
            text: Binding<String>,
            onCommandsReady: ((MarkdownCommands) -> Void)?,
            onOpenURL: ((String) -> Void)?
        ) {
            textBinding = text
            self.onCommandsReady = onCommandsReady
            self.onOpenURL = onOpenURL
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

        /// Schemes the host is allowed to open from a clicked link.
        ///
        /// Notes are plain files in a vault that may be synced or shared, so
        /// their contents are not necessarily authored by the person clicking.
        /// A `file://` link would open an arbitrary local file with its default
        /// handler on a single click, with no confirmation. The package decides
        /// what counts as a link click, so it filters here rather than trusting
        /// every host to.
        private static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

        private func handleOpenURL(_ url: String) {
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            // A missing scheme is fine — hosts commonly prefix https:// for
            // bare text like "example.com". Only reject schemes we know about
            // and disallow. Kept on one line: a wrapped multi-clause condition
            // makes SwiftFormat move the brace down, which SwiftLint rejects.
            let scheme = URL(string: trimmed)?.scheme?.lowercased()
            if let scheme, !Self.allowedSchemes.contains(scheme) {
                NSLog("[MarkdownEditor] blocked link with disallowed scheme: \(scheme)")
                return
            }
            onOpenURL?(trimmed)
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

// MARK: - Content process recovery

extension EditorWebView.Coordinator: WKNavigationDelegate {
    /// WKWebView runs CodeMirror in a separate content process, and that
    /// process can be killed — under memory pressure, or by a WebKit crash. The
    /// page then goes blank and stays blank: nothing reset the bridge's ready
    /// flag, so every later message queued forever against a page that would
    /// never report ready again. In a menu-bar app that lives for weeks, the
    /// user met a dead editor and had to quit and relaunch.
    ///
    /// Reload the bundled HTML instead. The fresh page reports `ready`, which
    /// flushes the queue and re-pushes the current text and config, so the note
    /// comes back with whatever the binding still holds.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("[MarkdownEditor] web content process terminated — reloading the editor")
        prepareForReload()
        EditorWebView.loadBundledEditor(into: webView)
    }
}

/// A WKWebView that draws nothing in its own background so the parent
/// SwiftUI/AppKit blur material shows through.
private final class TransparentWebView: WKWebView {
    override var isOpaque: Bool {
        false
    }
}

/// JSON-encodes a string into a JS string literal (with surrounding quotes)
/// so it survives concatenation into a JSON arg.
private func jsonEscape(_ value: String) -> String {
    let data = (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8)
    return String(data: data, encoding: .utf8) ?? "\"\""
}
