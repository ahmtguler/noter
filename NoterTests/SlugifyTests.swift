@testable import Noter
import Testing

struct SlugifyTests {
    @Test
    func stripsLeadingHeadingMarkers() {
        #expect(Slugify.filename(from: "# Hello World") == "Hello World")
        #expect(Slugify.filename(from: "### Subhead") == "Subhead")
    }

    @Test
    func usesFirstNonEmptyLine() {
        #expect(Slugify.filename(from: "\n\n# Title\n\nbody") == "Title")
    }

    @Test
    func emptyInputFallsBackToUntitled() {
        #expect(Slugify.filename(from: "") == "Untitled")
        #expect(Slugify.filename(from: "   \n   ") == "Untitled")
    }

    @Test
    func removesInvalidFilesystemCharacters() {
        #expect(Slugify.filename(from: "Foo/Bar:Baz?") == "FooBarBaz")
    }

    @Test
    func capsAtMaxLength() {
        let long = String(repeating: "a", count: 200)
        let slug = Slugify.filename(from: long)
        #expect(slug.count <= Slugify.maxLength)
    }

    @Test
    func collapsesWhitespace() {
        #expect(Slugify.filename(from: "Hello    world\t\tagain") == "Hello world again")
    }

    @Test
    func titleStripsHeadingMarkers() {
        #expect(Slugify.title(from: "## My Note\n\ntext") == "My Note")
    }

    @Test
    func titleEmptyForBlankBody() {
        #expect(Slugify.title(from: "").isEmpty)
    }
}
