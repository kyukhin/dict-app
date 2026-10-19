// HistoryViewModel.swift

import Foundation

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var items: [HistoryItem] = []
    @Published var errorMessage: String?

    private let db: DatabaseService

    init(db: DatabaseService = .shared) {
        self.db = db
    }

    func load() async {
        do {
            items = try await db.fetchHistory()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() async {
        do {
            try await db.clearHistory()
            items = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Timestamp caption (#114)

/// Formats `history.looked_at` for the History row caption. Pure Foundation,
/// no actor isolation; the stored value and its SQL ordering stay unchanged.
enum HistoryTimestamp {
    /// Parses SQLite `datetime('now')` text (`YYYY-MM-DD HH:MM:SS`, always UTC).
    static func date(fromStored raw: String) -> Date? {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return parser.date(from: raw)
    }

    /// The device locale (region, 24-hour setting) with only the language
    /// replaced by the in-app one, so English in Russia still reads day-first.
    static func formattingLocale(language: Locale, device: Locale = .current) -> Locale {
        var components = Locale.Components(locale: device)
        components.languageComponents.languageCode = language.language.languageCode
        components.languageComponents.script = nil   // the device's script belongs to the device's language
        return Locale(components: components)
    }

    /// Row caption: user's time zone + in-app locale, relative for today/yesterday,
    /// short date otherwise. `nil` (missing or unparseable) hides the caption.
    /// RTL locales get a leading U+200F (RLM) so the line always reads right to left (#119).
    static func text(_ raw: String?, locale: Locale,
                     timeZone: TimeZone = .autoupdatingCurrent) -> String? {
        guard let raw, let date = date(fromStored: raw) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        formatter.formattingContext = .beginningOfSentence   // "Today", not "today"
        return (locale.language.characterDirection == .rightToLeft ? "\u{200F}" : "") + formatter.string(from: date)
    }
}
