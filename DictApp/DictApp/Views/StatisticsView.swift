// StatisticsView.swift
// Learning statistics (0166-learning-statistics.md, #164): one scrolling
// list, one section per block. The language switch on top; the goal, the
// streak and the 30-day chart count every language, the other blocks the
// chosen one. One column, at most 700 pt wide on iPad; mirrored in Arabic.

import Charts
import SwiftUI

struct StatisticsView: View {
    @StateObject private var vm = StatisticsViewModel()
    @Environment(\.locale) private var locale

    /// The column's width on iPad.
    static let maxWidth: CGFloat = 700

    var body: some View {
        GeometryReader { geometry in
            List {
                if !vm.isLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if vm.isEmpty {
                    Text("stats.empty")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("stats_empty")
                } else {
                    if vm.learned.count > 1, let language = vm.language {
                        Section {
                            LearningLanguagePicker(languages: vm.learned, selection: Binding(
                                get: { language },
                                set: { lang in Task { await vm.select(lang) } }
                            ), identifier: "stats_language_switch")
                        }
                    }
                    todaySection
                    streakSection
                    Section("stats.last30") {
                        ThirtyDayChart(points: vm.series, goal: vm.goal.goal, streak: vm.streak)
                    }
                    listsSection
                    accuracySection
                    hardestSection
                    conjugationSections
                }
            }
            .contentMargins(.horizontal, max(0, (geometry.size.width - Self.maxWidth) / 2), for: .scrollContent)
            .accessibilityIdentifier("stats_view")
        }
        .navigationTitle("stats.title")
        .task {
            await vm.load()
        }
    }

    // MARK: Blocks

    /// Exercises of every language against the goal; the rest of the
    /// chosen language, as a run's summary counts them.
    private var todaySection: some View {
        Section("learn.today") {
            StatRow("run.summary.exercises", id: "stats_today_exercises") {
                Text("stats.of \(vm.goal.answered) \(vm.goal.goal)")
            }
            StatRow("run.summary.newWords", id: "stats_today_new") {
                Text(vm.blocks.today.newWords, format: .number)
            }
            StatRow("run.summary.reviewed", id: "stats_today_reviewed") {
                Text(vm.blocks.today.reviewedWords, format: .number)
            }
            StatRow("run.summary.accuracy", id: "stats_today_accuracy") {
                Self.percent(vm.blocks.today.accuracy)
            }
            StatRow("run.summary.time", id: "stats_today_time") {
                Text(Duration.milliseconds(vm.blocks.today.timeMs), format: .time(pattern: .minuteSecond))
            }
        }
    }

    private var streakSection: some View {
        Section("stats.streak") {
            StatRow("stats.streak.current", id: "stats_streak_current") {
                Text("stats.count.days \(vm.streak.current)")
            }
            StatRow("stats.streak.best", id: "stats_streak_best") {
                Text("stats.count.days \(vm.streak.best)")
            }
            StatRow("stats.streak.freezes", id: "stats_streak_freeze") {
                Text("stats.of \(vm.streak.freezes) \(Streak.maxFreezes)")
            }
            StreakCalendarView(streak: vm.streak, today: vm.today)
        }
    }

    @ViewBuilder
    private var listsSection: some View {
        if !vm.blocks.lists.isEmpty {
            Section("stats.lists") {
                ForEach(vm.blocks.lists) { row in
                    ListProgressRow(title: StatisticsViewModel.listTitle(row.list, locale: locale),
                                    progress: row.progress, forecast: row.forecast,
                                    forecastID: "stats_list_forecast_\(row.id.rawValue)")
                        .accessibilityIdentifier("stats_list_\(row.id.rawValue)")
                }
            }
        }
    }

    private var accuracySection: some View {
        Section("stats.accuracy") {
            AccuracyRow(title: Text("learn.trainer.recognition"), tally: vm.blocks.accuracy.recognition,
                        id: "stats_accuracy_recognition")
            AccuracyRow(title: Text("learn.trainer.production"), tally: vm.blocks.accuracy.production,
                        id: "stats_accuracy_production")
        }
    }

    @ViewBuilder
    private var hardestSection: some View {
        if !vm.blocks.hardestWords.isEmpty {
            Section("stats.hardest") {
                ForEach(Array(vm.blocks.hardestWords.enumerated()), id: \.element.id) { index, row in
                    HardWordRow(row: row, id: "stats_hardest_\(index + 1)")
                }
            }
        }
    }

    /// Shown once the drill (E5) has answers in the last 30 days.
    @ViewBuilder
    private var conjugationSections: some View {
        if !vm.blocks.tenses.isEmpty {
            Section("stats.conjugation") {
                TenseChart(tenses: vm.blocks.tenses)
                ForEach(vm.blocks.tenses) { row in
                    AccuracyRow(title: Text(verbatim: ConjugationTense.title(of: row.tense, locale: locale)),
                                tally: row.tally, id: "stats_tense_\(row.tense)")
                }
            }
            if !vm.blocks.hardestVerbs.isEmpty {
                Section("stats.hardestVerbs") {
                    ForEach(Array(vm.blocks.hardestVerbs.enumerated()), id: \.element.id) { index, row in
                        HardWordRow(row: row, id: "stats_hardest_verb_\(index + 1)")
                    }
                }
            }
        }
    }

    /// "87%", or a dash without answers.
    static func percent(_ value: Double?) -> Text {
        guard let value else { return Text(verbatim: "—") }
        return Text(value, format: .percent.precision(.fractionLength(0)))
    }
}

// MARK: - Rows

/// A title and a number; `id` on the number, for UI tests.
private struct StatRow: View {
    let title: LocalizedStringKey
    let id: String
    let value: Text

    init(_ title: LocalizedStringKey, id: String, @ViewBuilder value: () -> Text) {
        self.title = title
        self.id = id
        self.value = value()
    }

    var body: some View {
        LabeledContent {
            value
                .monospacedDigit()
                .accessibilityIdentifier(id)
        } label: {
            Text(title)
        }
    }
}

/// "Recognition · 412 answers · 87%"; `id` on the percentage.
private struct AccuracyRow: View {
    let title: Text
    let tally: Tally
    let id: String

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Text("stats.accuracy.answers \(tally.answers)")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                StatisticsView.percent(tally.accuracy)
                    .monospacedDigit()
                    .accessibilityIdentifier(id)
            }
        } label: {
            title
        }
    }
}

/// A hardest word or verb: its term and meaning, "5 mistakes · 62%". It
/// opens its Definition when its entry resolves.
private struct HardWordRow: View {
    let row: StatisticsViewModel.WordRow
    let id: String
    @Environment(\.locale) private var locale

    var body: some View {
        if let entry = row.entry {
            NavigationLink(value: entry) {
                content
            }
            .accessibilityIdentifier(id)
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(id)
        }
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.word.term)
                    .font(.body.weight(.medium))
                if !row.meaning.isEmpty {
                    Text(verbatim: row.meaning)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Text("stats.hardest.score \(row.word.tally.wrong) \(ChartSummary.percent(row.word.tally.accuracy ?? 0, locale))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// A list's title, its learned / learning / new bar and numbers, and the
/// forecast.
private struct ListProgressRow: View {
    let title: String
    let progress: ListProgress
    let forecast: Forecast?
    let forecastID: String
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title)
                .font(.headline)
            ListProgressBar(progress: progress)
            (Text("stats.list.learned \(progress.learned)") + Text(verbatim: " · ")
                + Text("stats.list.learning \(progress.learning)") + Text(verbatim: " · ")
                + Text("stats.list.new \(progress.new)"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let forecast {
                Text(verbatim: StatisticsViewModel.forecastText(forecast, locale: locale))
                    .font(.footnote)
                    .accessibilityIdentifier(forecastID)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }
}

/// Learned, learning and new words of a list, from the leading edge. The
/// numbers next to it carry it for VoiceOver.
struct ListProgressBar: View {
    let progress: ListProgress

    var body: some View {
        GeometryReader { geometry in
            let total = CGFloat(max(progress.total, 1))
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.green)
                    .frame(width: geometry.size.width * CGFloat(progress.learned) / total)
                Rectangle()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: geometry.size.width * CGFloat(progress.learning) / total)
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

// MARK: - Calendar

/// The last 5 weeks, Monday first: goal met, frozen, missed; today
/// outlined. Each day is one accessibility element, read as "3 November,
/// goal met"; its value is the mark (`met`, `frozen`, `missed`, `open`).
private struct StreakCalendarView: View {
    let streak: StreakState
    let today: LearnDay
    @Environment(\.locale) private var locale

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 6) {
            GridRow {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, symbol in
                    Text(verbatim: symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            ForEach(StreakCalendar.days(today: today), id: \.first) { week in
                GridRow {
                    ForEach(week, id: \.self) { day in
                        cell(day)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// The very short weekday names, Monday first.
    private var weekdays: [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return Array(symbols.dropFirst() + symbols.prefix(1))
    }

    @ViewBuilder
    private func cell(_ day: LearnDay) -> some View {
        if day > today {
            Color.clear
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
        } else {
            let mark = streak.mark(on: day)
            ZStack {
                Circle()
                    .fill(fill(mark))
                if mark == .frozen {
                    Image(systemName: "snowflake")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan)
                } else {
                    Text(verbatim: day.dayOfMonth(locale: locale))
                        .font(.caption2.weight(mark == .met ? .bold : .regular))
                        .foregroundStyle(mark == .met ? Color.white : Color.primary)
                }
            }
            .frame(width: 32, height: 32)
            .overlay {
                if day == today {
                    Circle().strokeBorder(Color.primary, lineWidth: 2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: ChartSummary.day(day, mark: mark, locale: locale)))
            .accessibilityValue(Text(verbatim: mark.rawValue))
            .accessibilityIdentifier("stats_streak_day_\(day.rawValue)")
        }
    }

    private func fill(_ mark: DayMark) -> Color {
        switch mark {
        case .met: return .accentColor
        case .frozen: return .cyan.opacity(0.2)
        case .missed: return .red.opacity(0.2)
        case .open: return .clear
        case .none: return .secondary.opacity(0.08)
        }
    }
}

// MARK: - Charts

/// Exercises per day, every language, with a dashed line at the current
/// goal; days whose goal was met in the accent colour. The oldest day is at
/// the leading edge and today at the trailing one, so in Arabic the chart
/// reads right to left: the plot itself is laid out left to right and the
/// days are placed by hand. VoiceOver reads it as one summary.
private struct ThirtyDayChart: View {
    let points: [DayPoint]
    let goal: Int
    let streak: StreakState
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        VStack(spacing: 6) {
            chart
            HStack {
                Text(verbatim: points.first?.day.dayAndMonth(locale: locale) ?? "")
                    .accessibilityIdentifier("stats_chart_start")
                Spacer()
                Text("learn.today")
                    .accessibilityIdentifier("stats_chart_end")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var chart: some View {
        let rtl = direction == .rightToLeft
        let last = max(points.count - 1, 0)
        return Chart {
            ForEach(Array(points.enumerated()), id: \.element.day) { index, point in
                bar(point, at: Double(rtl ? last - index : index))
            }
            RuleMark(y: .value("Goal", goal))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Color.primary.opacity(0.6))
        }
        .chartXScale(domain: -0.5...(Double(last) + 0.5))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: rtl ? .leading : .trailing)
        }
        .frame(height: 160)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: ChartSummary.last30(points, streak: streak, locale: locale)))
        .accessibilityIdentifier("stats_chart_30d")
    }

    /// A day's bar from 0, centred on `x`; accent when its goal was met.
    private func bar(_ point: DayPoint, at x: Double) -> some ChartContent {
        let color: Color = streak.mark(on: point.day) == .met ? .accentColor : .secondary.opacity(0.35)
        let start: Double = x - 0.35, end: Double = x + 0.35
        let zero = 0, height: Int = point.exercises
        let mark = RectangleMark(xStart: .value("Day", start), xEnd: .value("Day", end),
                                 yStart: .value("Exercises", zero), yEnd: .value("Exercises", height))
        return mark.foregroundStyle(color)
    }
}

/// Accuracy by tense as horizontal bars from the leading edge, in the
/// tables' order. VoiceOver reads it as one summary.
private struct TenseChart: View {
    let tenses: [StatisticsViewModel.TenseRow]
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        let rtl = direction == .rightToLeft
        let sign = rtl ? -1.0 : 1.0
        Chart(tenses) { row in
            let share = row.tally.accuracy ?? 0
            BarMark(xStart: .value("Accuracy", 0.0), xEnd: .value("Accuracy", sign * share),
                    y: .value("Tense", ConjugationTense.title(of: row.tense, locale: locale)))
                .foregroundStyle(Color.accentColor)
                .annotation(position: rtl ? .leading : .trailing) {
                    Text(verbatim: ChartSummary.percent(share, locale))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
        .chartXScale(domain: rtl ? -1.25...0 : 0...1.25)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: rtl ? .trailing : .leading)
        }
        .frame(height: CGFloat(tenses.count) * 34 + 8)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: ChartSummary.tenses(tenses.map { ($0.tense, $0.tally) }, locale: locale)))
        .accessibilityIdentifier("stats_chart_tenses")
        .padding(.vertical, 4)
    }
}
