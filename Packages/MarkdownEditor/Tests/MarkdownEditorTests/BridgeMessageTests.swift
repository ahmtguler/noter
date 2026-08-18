import Foundation
@testable import MarkdownEditor
import Testing

/// The JS side owns the list of style names and Swift mirrors it in
/// `MarkdownStyle`. Nothing enforces that the two stay in step, so decoding has
/// to survive them drifting apart.
struct BridgeMessageTests {
    private func decode(_ json: String) throws -> InboundMessage {
        try JSONDecoder().decode(InboundMessage.self, from: Data(json.utf8))
    }

    @Test
    func decodesAKnownStyleSet() throws {
        let message = try decode(#"{"kind":"selectionChanged","styles":["bold","code"]}"#)
        guard case let .selectionChanged(styles) = message else {
            Issue.record("expected selectionChanged, got \(message)")
            return
        }
        #expect(styles == [.bold, .code])
    }

    /// Regression: decoding straight into `Set<MarkdownStyle>` threw on the
    /// first unrecognised name, and the throw was caught centrally and logged,
    /// so the whole message was dropped. One new style on the JS side would
    /// have frozen the entire toolbar rather than disabling one button.
    @Test
    func skipsUnknownStylesInsteadOfDroppingTheMessage() throws {
        let message = try decode(
            #"{"kind":"selectionChanged","styles":["bold","aStyleSwiftDoesNotKnow","code"]}"#
        )
        guard case let .selectionChanged(styles) = message else {
            Issue.record("expected selectionChanged, got \(message)")
            return
        }
        #expect(styles == [.bold, .code])
    }

    @Test
    func anEmptyStyleSetDecodes() throws {
        let message = try decode(#"{"kind":"selectionChanged","styles":[]}"#)
        guard case let .selectionChanged(styles) = message else {
            Issue.record("expected selectionChanged, got \(message)")
            return
        }
        #expect(styles.isEmpty)
    }

    /// An unknown *kind* is a different case: there is no sensible handling, so
    /// it should still throw rather than be silently swallowed.
    @Test
    func anUnknownMessageKindStillThrows() {
        #expect(throws: (any Error).self) {
            try decode(#"{"kind":"somethingNew"}"#)
        }
    }

    @Test
    func decodesTextChanged() throws {
        // Needs ##"…"## rather than #"…"#: the JSON contains `"#`, which would
        // otherwise close a single-pound raw string early.
        let message = try decode(##"{"kind":"textChanged","text":"# Hello"}"##)
        guard case let .textChanged(text) = message else {
            Issue.record("expected textChanged, got \(message)")
            return
        }
        #expect(text == "# Hello")
    }
}
