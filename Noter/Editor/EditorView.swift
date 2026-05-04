import AppKit
import SwiftUI

/// SwiftUI wrapper around an `NSTextView` configured for plaintext-with-attributes
/// markdown editing. The `MarkdownStyler` re-applies attributes on every edit.
struct EditorView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            fatalError("scrollableTextView did not produce an NSTextView")
        }

        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isRichText = false
        textView.usesFindBar = false
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .textColor
        textView.textContainerInset = NSSize(width: 24, height: 16)
        textView.smartInsertDeleteEnabled = false
        textView.usesFontPanel = false

        let styler = MarkdownStyler()
        textView.textStorage?.delegate = styler
        context.coordinator.styler = styler

        textView.string = text
        if let storage = textView.textStorage {
            styler.restyleAll(storage)
        }
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            // External update — keep selection if it still fits, otherwise clamp.
            let oldSelection = textView.selectedRange()
            textView.string = text
            let length = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(
                location: min(oldSelection.location, length),
                length: 0
            ))
            if let storage = textView.textStorage {
                context.coordinator.styler?.restyleAll(storage)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var styler: MarkdownStyler?
        weak var textView: NSTextView?

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}
