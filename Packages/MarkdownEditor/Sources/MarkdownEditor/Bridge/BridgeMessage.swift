import Foundation

/// Messages the JS layer can send to Swift. Decoded from the `kind` field.
enum InboundMessage: Decodable {
    case ready
    case textChanged(text: String)
    case selectionChanged(styles: Set<MarkdownStyle>)
    case logging(level: String, message: String)

    enum CodingKeys: String, CodingKey {
        case kind
        case text
        case styles
        case level
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "ready":
            self = .ready
        case "textChanged":
            self = try .textChanged(text: container.decode(String.self, forKey: .text))
        case "selectionChanged":
            self = try .selectionChanged(styles: container.decode(Set<MarkdownStyle>.self, forKey: .styles))
        case "log":
            self = try .logging(
                level: container.decode(String.self, forKey: .level),
                message: container.decode(String.self, forKey: .message)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown message kind \(kind)"
            )
        }
    }
}

/// Messages Swift sends to JS. Encoded as JSON and applied via `evaluateJavaScript`.
enum OutboundMessage {
    case setText(String)
    case applyConfig(EditorConfiguration)
    case execute(command: BridgeCommand, arg: String?)

    func javascript() -> String {
        switch self {
        case let .setText(text):
            return "window.bridge.setText(\(jsString(text)))"
        case let .applyConfig(config):
            let json = (try? JSONEncoder().encode(config)) ?? Data()
            let raw = String(data: json, encoding: .utf8) ?? "{}"
            return "window.bridge.applyConfig(\(raw))"
        case let .execute(command, arg):
            let argLiteral = arg.map { jsString($0) } ?? "null"
            return "window.bridge.exec(\(jsString(command.rawValue)), \(argLiteral))"
        }
    }

    /// Encodes a String as a JSON string literal so it survives `evaluateJavaScript`.
    private func jsString(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("\"\"".utf8)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }
}

/// Command names known by the JS side. Strings keep the wire-format stable
/// across builds; renames in Swift don't accidentally break the bridge.
enum BridgeCommand: String {
    case bold
    case italic
    case underline
    case strikethrough
    case code
    case codeBlock
    case heading
    case bulletList
    case numberedList
    case todo
    case quote
    case link
    case focus
}
