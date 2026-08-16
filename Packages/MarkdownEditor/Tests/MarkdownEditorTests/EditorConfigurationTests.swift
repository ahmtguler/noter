import Foundation
@testable import MarkdownEditor
import Testing

struct EditorConfigurationTests {
    @Test
    func defaultsAreSane() {
        let config = EditorConfiguration.default
        #expect(config.theme == .system)
        #expect(config.fontSize == 14)
        #expect(config.spellCheck)
        #expect(config.smartListContinuation)
        #expect(config.revealMarkersOnCursor)
        #expect(config.lineWrap)
    }

    @Test
    func roundtripsAsJSON() throws {
        let config = EditorConfiguration(theme: .dark, fontSize: 16, spellCheck: false)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(EditorConfiguration.self, from: data)
        #expect(decoded == config)
    }
}
