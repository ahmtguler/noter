import Foundation

struct Note: Identifiable, Equatable {
    var url: URL
    var body: String
    var modifiedAt: Date
    var openedAt: Date?

    var id: URL {
        url
    }

    var title: String {
        let derived = Slugify.title(from: body)
        if !derived.isEmpty {
            return derived
        }
        return url.deletingPathExtension().lastPathComponent
    }

    var characterCount: Int {
        body.count
    }
}
