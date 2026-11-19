import Foundation

struct TrendPoint: Identifiable, Equatable {
    let id: UUID
    let index: Int
    let date: Date
    let hours: Double
    let cumulativeProfit: Decimal
}

struct Breakdown: Identifiable, Equatable {
    let name: String
    let sessions: Int
    let hours: Double
    let profit: Decimal
    var wins: Int = 0
    /// Порядок для фиксированных групп (дни недели, время суток); иначе 0.
    var order: Int = 0

    var id: String { name }
    var hourlyRate: Decimal {
        guard hours > 0 else { return 0 }
        return profit / Decimal(hours)
    }
    var averageProfit: Decimal { sessions == 0 ? 0 : profit / Decimal(sessions) }
    var winRate: Double { sessions == 0 ? 0 : Double(wins) / Double(sessions) }
}

struct HistogramBin: Identifiable, Equatable {
    let lower: Double
    let upper: Double
    let count: Int
    var id: Double { lower }
    var mid: Double { (lower + upper) / 2 }
}

struct SessionAnalytics: Equatable {
    let totalProfit: Decimal
    let totalHours: Double
    let sessionCount: Int
    let wins: Int
    let losses: Int
    let averageWin: Decimal
    let averageLoss: Decimal
    let bestSession: PokerSession?
    let worstSession: PokerSession?
    let longestSession: PokerSession?
    let totalBuyIn: Decimal
    let totalRebuys: Int
    let sessionsWithRebuy: Int
    let trend: [TrendPoint]
    let byVenue: [Breakdown]
    let byGame: [Breakdown]
    let byStakes: [Breakdown]
    let byWeekday: [Breakdown]
    let byTimeOfDay: [Breakdown]
    let byLength: [Breakdown]
    let byMonth: [Breakdown]
    let byYear: [Breakdown]
    let resultHistogram: [HistogramBin]
    /// Наибольшая просадка от пика накопленного профита (положительное число, USD).
    let maxDrawdown: Decimal
    let peakProfit: Decimal
    /// Текущая серия: >0 — подряд в плюс, <0 — подряд в минус.
    let currentStreak: Int
    let longestWinStreak: Int
    let longestLossStreak: Int
    /// Стандартное отклонение результата одной сессии, USD.
    let standardDeviation: Double
    /// Стандартное отклонение за час, USD (как в трекерах: sqrt(Σ(p − h·w)² / Σh)).
    let standardDeviationPerHour: Double
    /// Большие блайнды в час — только по сессиям, где лимит понятен (например, «50/100»).
    let bigBlindsPerHour: Double?
    let bigBlindsWon: Double?
    let firstDate: Date?
    let lastDate: Date?

    var hourlyRate: Decimal {
        guard totalHours > 0 else { return 0 }
        return totalProfit / Decimal(totalHours)
    }
    var winRate: Double { sessionCount == 0 ? 0 : Double(wins) / Double(sessionCount) }
    var averageSessionHours: Double { sessionCount == 0 ? 0 : totalHours / Double(sessionCount) }
    var averageProfit: Decimal { sessionCount == 0 ? 0 : totalProfit / Decimal(sessionCount) }
    var averageBuyIn: Decimal { sessionCount == 0 ? 0 : totalBuyIn / Decimal(sessionCount) }
    var roi: Double { totalBuyIn > 0 ? (totalProfit / totalBuyIn).doubleValue : 0 }
    var rebuyRate: Double { sessionCount == 0 ? 0 : Double(sessionsWithRebuy) / Double(sessionCount) }
    var currentDrawdown: Decimal { max(0, peakProfit - totalProfit) }
    var bestMonth: Breakdown? { byMonth.max { $0.profit < $1.profit } }
    var worstMonth: Breakdown? { byMonth.min { $0.profit < $1.profit } }
    var winningMonths: Int { byMonth.filter { $0.profit > 0 }.count }
    var sessionsPerWeek: Double {
        guard let firstDate, let lastDate, sessionCount > 1 else { return Double(sessionCount) }
        let weeks = max(1, lastDate.timeIntervalSince(firstDate) / (7 * 24 * 3600))
        return Double(sessionCount) / weeks
    }
}

enum AnalyticsEngine {
    static func calculate(_ sessions: [PokerSession], calendar: Calendar = .current) -> SessionAnalytics {
        let totalProfit = sessions.reduce(Decimal.zero) { $0 + $1.profit }
        let totalHours = sessions.reduce(0.0) { $0 + $1.durationHours }
        let winning = sessions.filter { $0.profit > 0 }
        let losing = sessions.filter { $0.profit < 0 }
        let averageWin = winning.isEmpty ? 0 : winning.reduce(Decimal.zero) { $0 + $1.profit } / Decimal(winning.count)
        let averageLoss = losing.isEmpty ? 0 : losing.reduce(Decimal.zero) { $0 + $1.profit } / Decimal(losing.count)
        let sorted = sessions.sorted {
            if $0.date == $1.date { return $0.createdAt < $1.createdAt }
            return $0.date < $1.date
        }

        // Тренд, просадка, пик.
        var running = Decimal.zero
        var hours = 0.0
        var peak = Decimal.zero
        var drawdown = Decimal.zero
        var trend: [TrendPoint] = []
        trend.reserveCapacity(sorted.count)
        for (index, session) in sorted.enumerated() {
            running += session.profit
            hours += session.durationHours
            peak = max(peak, running)
            drawdown = max(drawdown, peak - running)
            trend.append(TrendPoint(id: session.id, index: index + 1, date: session.date, hours: hours, cumulativeProfit: running))
        }

        // Серии.
        var longestWin = 0, longestLoss = 0, run = 0
        for session in sorted {
            if session.profit > 0 { run = run > 0 ? run + 1 : 1 }
            else if session.profit < 0 { run = run < 0 ? run - 1 : -1 }
            else { run = 0 }
            longestWin = max(longestWin, run)
            longestLoss = max(longestLoss, -run)
        }
        var streak = 0
        for session in sorted.reversed() {
            guard session.profit != 0 else { break }
            let won = session.profit > 0
            if streak == 0 { streak = won ? 1 : -1; continue }
            if (streak > 0) == won { streak += won ? 1 : -1 } else { break }
        }

        // Разброс.
        let profits = sessions.map(\.profit.doubleValue)
        let mean = profits.isEmpty ? 0 : profits.reduce(0, +) / Double(profits.count)
        let variance = profits.count > 1 ? profits.reduce(0) { $0 + pow($1 - mean, 2) } / Double(profits.count - 1) : 0
        let hourly = totalHours > 0 ? totalProfit.doubleValue / totalHours : 0
        let hourVariance = totalHours > 0
            ? sessions.reduce(0.0) { $0 + pow($1.profit.doubleValue - hourly * $1.durationHours, 2) } / totalHours
            : 0

        // BB/час.
        var bbWon = 0.0, bbHours = 0.0
        for session in sessions {
            guard let bb = StakesParser.bigBlind(session.stakes), bb > 0, session.durationHours > 0 else { continue }
            bbWon += session.nativeProfit.doubleValue / bb
            bbHours += session.durationHours
        }

        return SessionAnalytics(
            totalProfit: totalProfit,
            totalHours: totalHours,
            sessionCount: sessions.count,
            wins: winning.count,
            losses: losing.count,
            averageWin: averageWin,
            averageLoss: averageLoss,
            bestSession: sessions.max { $0.profit < $1.profit },
            worstSession: sessions.min { $0.profit < $1.profit },
            longestSession: sessions.max { $0.durationMinutes < $1.durationMinutes },
            totalBuyIn: sessions.reduce(Decimal.zero) { $0 + $1.buyInUSD },
            totalRebuys: sessions.reduce(0) { $0 + $1.rebuyCount },
            sessionsWithRebuy: sessions.filter { $0.rebuyCount > 0 }.count,
            trend: trend,
            byVenue: breakdown(sessions, key: { $0.venue }),
            byGame: breakdown(sessions, key: { $0.game }),
            byStakes: breakdown(sessions, key: { $0.stakes }),
            byWeekday: weekdayBreakdown(sessions, calendar: calendar),
            byTimeOfDay: timeOfDayBreakdown(sessions, calendar: calendar),
            byLength: lengthBreakdown(sessions),
            byMonth: periodBreakdown(sessions, calendar: calendar, components: [.year, .month], format: "yyyy-MM"),
            byYear: periodBreakdown(sessions, calendar: calendar, components: [.year], format: "yyyy"),
            resultHistogram: histogram(profits),
            maxDrawdown: drawdown,
            peakProfit: peak,
            currentStreak: streak,
            longestWinStreak: longestWin,
            longestLossStreak: longestLoss,
            standardDeviation: sqrt(variance),
            standardDeviationPerHour: sqrt(hourVariance),
            bigBlindsPerHour: bbHours > 0 ? bbWon / bbHours : nil,
            bigBlindsWon: bbHours > 0 ? bbWon : nil,
            firstDate: sorted.first?.date,
            lastDate: sorted.last?.date
        )
    }

    static func sessions(_ sessions: [PokerSession], in range: AnalyticsRange, now: Date = .now, calendar: Calendar = .current) -> [PokerSession] {
        guard let start = range.startDate(now: now, calendar: calendar) else { return sessions }
        return sessions.filter { $0.date >= start && $0.date <= now }
    }

    // MARK: - Breakdowns

    private static func make(_ name: String, _ values: [PokerSession], order: Int = 0) -> Breakdown {
        Breakdown(
            name: name,
            sessions: values.count,
            hours: values.reduce(0) { $0 + $1.durationHours },
            profit: values.reduce(Decimal.zero) { $0 + $1.profit },
            wins: values.filter { $0.profit > 0 }.count,
            order: order
        )
    }

    private static func breakdown(_ sessions: [PokerSession], key: (PokerSession) -> String) -> [Breakdown] {
        Dictionary(grouping: sessions) { key($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { name, values in make(name.isEmpty ? "Unspecified" : name, values) }
            .sorted { lhs, rhs in
                if lhs.profit == rhs.profit { return lhs.name < rhs.name }
                return lhs.profit > rhs.profit
            }
    }

    private static func weekdayBreakdown(_ sessions: [PokerSession], calendar: Calendar) -> [Breakdown] {
        let symbols = calendar.shortWeekdaySymbols
        let grouped = Dictionary(grouping: sessions) { calendar.component(.weekday, from: $0.date) }
        // Неделя с понедельника.
        return (0..<7).map { offset in
            let weekday = (offset + 1) % 7 + 1 // 2,3,4,5,6,7,1
            return make(symbols[weekday - 1], grouped[weekday] ?? [], order: offset)
        }
    }

    static let dayParts: [(name: String, hours: Range<Int>)] = [
        ("Morning", 6..<12), ("Afternoon", 12..<18), ("Evening", 18..<24), ("Night", 0..<6)
    ]

    private static func timeOfDayBreakdown(_ sessions: [PokerSession], calendar: Calendar) -> [Breakdown] {
        dayParts.enumerated().map { index, part in
            make(part.name, sessions.filter { part.hours.contains(calendar.component(.hour, from: $0.date)) }, order: index)
        }
    }

    static let lengthBuckets: [(name: String, minutes: Range<Int>)] = [
        ("< 2h", 0..<120), ("2–4h", 120..<240), ("4–6h", 240..<360), ("6–8h", 360..<480), ("8h+", 480..<Int.max)
    ]

    private static func lengthBreakdown(_ sessions: [PokerSession]) -> [Breakdown] {
        lengthBuckets.enumerated().map { index, bucket in
            make(bucket.name, sessions.filter { bucket.minutes.contains($0.durationMinutes) }, order: index)
        }
    }

    private static func periodBreakdown(_ sessions: [PokerSession], calendar: Calendar, components: Set<Calendar.Component>, format: String) -> [Breakdown] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        let grouped = Dictionary(grouping: sessions) { session -> Date in
            calendar.date(from: calendar.dateComponents(components, from: session.date)) ?? session.date
        }
        return grouped.keys.sorted().enumerated().map { index, start in
            make(formatter.string(from: start), grouped[start] ?? [], order: index)
        }
    }

    private static func histogram(_ values: [Double]) -> [HistogramBin] {
        guard let minValue = values.min(), let maxValue = values.max(), values.count > 1, maxValue > minValue else {
            return values.isEmpty ? [] : [HistogramBin(lower: (values.first ?? 0) - 1, upper: (values.first ?? 0) + 1, count: values.count)]
        }
        let binCount = min(12, max(4, Int(Double(values.count).squareRoot().rounded(.up))))
        let rawWidth = (maxValue - minValue) / Double(binCount)
        let magnitude = pow(10, floor(log10(rawWidth)))
        let width = ([1.0, 2.0, 2.5, 5.0, 10.0].first { $0 * magnitude >= rawWidth } ?? 10) * magnitude
        let start = floor(minValue / width) * width
        var bins: [HistogramBin] = []
        var lower = start
        while lower <= maxValue {
            let upper = lower + width
            let count = values.filter { $0 >= lower && ($0 < upper || (upper > maxValue && $0 <= maxValue)) }.count
            bins.append(HistogramBin(lower: lower, upper: upper, count: count))
            lower = upper
        }
        return bins
    }
}

enum StakesParser {
    /// "50/100" → 100, "$1/$2" → 2, "100/200/400" → 200, "1-2" → 2.
    static func bigBlind(_ stakes: String) -> Double? {
        let parts = stakes
            .replacingOccurrences(of: ",", with: ".")
            .split(whereSeparator: { $0 == "/" || $0 == "-" || $0 == "\\" })
            .map { $0.filter { $0.isNumber || $0 == "." } }
            .compactMap(Double.init)
        guard parts.count >= 2, parts[1] > 0 else { return nil }
        return parts[1]
    }
}

enum AnalyticsRange: String, CaseIterable, Identifiable {
    case month = "30D"
    case quarter = "90D"
    case ytd = "YTD"
    case year = "1Y"
    case all = "All"
    var id: String { rawValue }

    func startDate(now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .month: calendar.date(byAdding: .day, value: -30, to: now)
        case .quarter: calendar.date(byAdding: .day, value: -90, to: now)
        case .ytd: calendar.date(from: calendar.dateComponents([.year], from: now))
        case .year: calendar.date(byAdding: .year, value: -1, to: now)
        case .all: nil
        }
    }
}
