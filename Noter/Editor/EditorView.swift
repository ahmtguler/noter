import AppKit
import SwiftUI

/// SwiftUI wrapper around `MarkdownTextView` configured for plaintext-with-attributes
/// markdown editing. The `MarkdownStyler` re-applies attributes on every edit;
/// keyboard shortcuts and toolbar buttons go through `EditorCommands`.
struct EditorView: NSViewRepresentable {
    @Binding var text: String
    let commands: EditorCommands

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]

        let textView = MarkdownTextView(frame: .zero)
        textView.commands = commands
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
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )

        let styler = MarkdownStyler()
        textView.textStorage?.delegate = styler
        context.coordinator.styler = styler
        textView.string = text
        if let storage = textView.textStorage {
            styler.restyleAll(storage)
        }
        context.coordinator.textView = textView
        commands.textView = textView

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
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
