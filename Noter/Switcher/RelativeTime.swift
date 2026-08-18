import Foundation

/// Pretty-printer for "X ago" timestamps that floors below a minute (we
/// don't want twitching seconds on every tick of the clock) and uses the
/// largest fitting unit otherwise. Locale-aware via
/// `RelativeDateTimeFormatter`.
///
/// Main-actor isolated because the cached formatter is shared mutable state:
/// `RelativeDateTimeFormatter` is a class and isn't thread-safe, so the Swift 6
/// diagnostic here is pointing at a real hazard rather than a technicality.
/// Both call sites are SwiftUI view bodies, which are already on the main
/// actor, so confining it costs nothing and keeps the formatter cached.
@MainActor
enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static func string(from date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 {
            return "less than a minute ago"
        }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
