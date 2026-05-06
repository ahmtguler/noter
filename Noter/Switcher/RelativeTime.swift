import Foundation

/// Pretty-printer for "X ago" timestamps that floors below a minute (we
/// don't want twitching seconds on every tick of the clock) and uses the
/// largest fitting unit otherwise. Locale-aware via
/// `RelativeDateTimeFormatter`.
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
