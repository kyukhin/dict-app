// LearningService.swift
// Learning words with spaced repetition (0131-learning.md): the services
// around the store. The clock (#157).

import Foundation

// MARK: - Clock (#157)

/// The learning day of `now`. A day starts at 4 AM local time, as in Anki:
/// an answer at 00:30 counts for the day before (Kirill, 2026-11-03).
/// Injected into the view models; the store takes `today` as an argument.
struct LearningClock: Sendable {
    /// The hour a learning day starts at.
    static let dayStartHour = 4

    var now: @Sendable () -> Date = { Date() }
    /// Gregorian, in the current time zone.
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }()

    var today: LearnDay { Self.day(at: now(), calendar: calendar) }

    /// The local date of `date`, or the day before when its local hour is
    /// under 4. Calendar arithmetic, never "minus 4 hours": on a
    /// daylight-saving change day the two differ for an hour.
    static func day(at date: Date, calendar: Calendar) -> LearnDay {
        guard calendar.component(.hour, from: date) < dayStartHour,
              let dayBefore = calendar.date(byAdding: .day, value: -1, to: date) else {
            return LearnDay(date: date, calendar: calendar)
        }
        return LearnDay(date: dayBefore, calendar: calendar)
    }
}
