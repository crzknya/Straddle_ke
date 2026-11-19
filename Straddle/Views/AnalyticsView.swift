import SwiftUI
import Charts

private enum AnalyticsTab: String, CaseIterable, Identifiable {
    case overview = "Stats"
    case charts = "Charts"
    case reports = "Reports"
    case calendar = "Calendar"
    var id: String { rawValue }
}

struct AnalyticsView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var tab: AnalyticsTab = .overview
    @State private var range: AnalyticsRange = .all
    @State private var venue: String?
    @State private var stakes: String?

    private var filtered: [PokerSession] {
        AnalyticsEngine.sessions(store.sessions, in: range).filter { session in
            (venue == nil || session.venue == venue) && (stakes == nil || session.stakes == stakes)
        }
    }
    private var analytics: SessionAnalytics { AnalyticsEngine.calculate(filtered) }

    var body: some View {
        ZStack {
            StraddleTheme.background.ignoresSafeArea()
            if store.sessions.isEmpty {
                EmptyStateView(icon: "chart.xyaxis.line", title: "Analytics await", message: "Your performance insights will build as you log sessions.").padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        Picker("Section", selection: $tab) {
                            ForEach(AnalyticsTab.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        if tab != .calendar {
                            Picker("Range", selection: $range) {
                                ForEach(AnalyticsRange.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                        filterBar

                        let data = analytics
                        if tab == .calendar {
                            ResultsCalendar(sessions: store.sessions.filter { session in
                                (venue == nil || session.venue == venue) && (stakes == nil || session.stakes == stakes)
                            })
                        } else if filtered.isEmpty {
                            EmptyStateView(icon: "calendar.badge.exclamationmark", title: "No sessions", message: "Choose a longer timeframe or clear filters.").straddleCard()
                        } else {
                            switch tab {
                            case .overview: OverviewSection(analytics: data)
                            case .charts: ChartsSection(analytics: data)
                            case .reports: ReportsSection(analytics: data)
                            case .calendar: EmptyView()
                            }
                        }
                        Text("All amounts in USD, converted with the rate saved in each session.")
                            .font(.caption).foregroundStyle(StraddleTheme.secondaryText)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Analytics")
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            filterMenu(title: venue ?? "All venues", icon: "mappin.and.ellipse", selection: $venue, options: store.recentValues(\.venue, limit: 50))
            filterMenu(title: stakes ?? "All stakes", icon: "dollarsign.circle", selection: $stakes, options: store.recentValues(\.stakes, limit: 50))
            Spacer(minLength: 0)
        }
    }

    private func filterMenu(title: String, icon: String, selection: Binding<String?>, options: [String]) -> some View {
        Menu {
            Button("All") { selection.wrappedValue = nil }
            ForEach(options, id: \.self) { option in
                Button(option) { selection.wrappedValue = option }
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(selection.wrappedValue == nil ? StraddleTheme.surface : StraddleTheme.purple.opacity(0.35), in: Capsule())
        }
        .disabled(options.isEmpty)
    }
}

// MARK: - Shared bits

private func statLine(_ label: String, _ value: String, color: Color = .white) -> some View {
    HStack {
        Text(label).foregroundStyle(StraddleTheme.secondaryText)
        Spacer()
        Text(value).fontWeight(.semibold).monospacedDigit().foregroundStyle(color)
    }
}

private func card<Content: View>(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(StraddleTheme.secondaryText) }
        }
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .straddleCard()
}

private func profitColor(_ value: Decimal) -> Color { value >= 0 ? StraddleTheme.positive : StraddleTheme.negative }
private func profitColor(_ value: Double) -> Color { value >= 0 ? StraddleTheme.positive : StraddleTheme.negative }

private func compactUSD(_ value: Double) -> String {
    let absValue = abs(value)
    let sign = value < 0 ? "-" : ""
    if absValue >= 1000 { return sign + "$" + (absValue / 1000).formatted(.number.precision(.fractionLength(absValue >= 10_000 ? 0 : 1))) + "k" }
    return sign + "$" + absValue.formatted(.number.precision(.fractionLength(0)))
}

private func usdAxis() -> some AxisContent {
    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
        AxisValueLabel {
            if let amount = value.as(Double.self) { Text(compactUSD(amount)) }
        }
        .foregroundStyle(StraddleTheme.secondaryText)
    }
}

// MARK: - Overview

private struct OverviewSection: View {
    let analytics: SessionAnalytics

    var body: some View {
        let a = analytics
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: columns, spacing: 12) {
                MetricCard(title: "Net profit", value: a.totalProfit.signedCurrencyText, tint: profitColor(a.totalProfit))
                MetricCard(title: "Hourly rate", value: a.hourlyRate.signedCurrencyText, tint: profitColor(a.hourlyRate))
                MetricCard(title: "BB / hour", value: a.bigBlindsPerHour.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—", tint: StraddleTheme.cyan)
                MetricCard(title: "Win rate", value: a.winRate.formatted(.percent.precision(.fractionLength(0))), tint: StraddleTheme.purple)
                MetricCard(title: "Sessions", value: "\(a.sessionCount)", tint: StraddleTheme.purple)
                MetricCard(title: "Hours played", value: a.totalHours.formatted(.number.precision(.fractionLength(1))), tint: StraddleTheme.cyan)
            }

            card("Bankroll") {
                BankrollChart(points: a.trend)
            }

            card("Results") {
                statLine("Average result", a.averageProfit.signedCurrencyText, color: profitColor(a.averageProfit))
                statLine("Average win", a.averageWin.signedCurrencyText, color: StraddleTheme.positive)
                statLine("Average loss", a.averageLoss.signedCurrencyText, color: StraddleTheme.negative)
                statLine("Winning sessions", "\(a.wins) of \(a.sessionCount)")
                statLine("Losing sessions", "\(a.losses)")
                if let best = a.bestSession { statLine("Best session", best.profit.signedCurrencyText, color: StraddleTheme.positive) }
                if let worst = a.worstSession { statLine("Worst session", worst.profit.signedCurrencyText, color: StraddleTheme.negative) }
                if let bb = a.bigBlindsWon { statLine("Big blinds won", bb.formatted(.number.precision(.fractionLength(0)))) }
            }

            card("Variance", subtitle: "How much your results swing") {
                statLine("Std deviation / session", "$" + a.standardDeviation.formatted(.number.precision(.fractionLength(0))))
                statLine("Std deviation / hour", "$" + a.standardDeviationPerHour.formatted(.number.precision(.fractionLength(0))))
                statLine("Max drawdown", (-a.maxDrawdown).signedCurrencyText, color: a.maxDrawdown > 0 ? StraddleTheme.negative : .white)
                statLine("Below peak now", (-a.currentDrawdown).signedCurrencyText, color: a.currentDrawdown > 0 ? StraddleTheme.negative : .white)
                statLine("All-time high", a.peakProfit.signedCurrencyText)
                statLine("Longest winning streak", "\(a.longestWinStreak)")
                statLine("Longest losing streak", "\(a.longestLossStreak)")
                statLine("Current streak", a.currentStreak == 0 ? "—" : (a.currentStreak > 0 ? "\(a.currentStreak) W" : "\(-a.currentStreak) L"),
                         color: a.currentStreak >= 0 ? StraddleTheme.positive : StraddleTheme.negative)
            }

            card("Buy-ins") {
                statLine("Total bought in", a.totalBuyIn.currencyText)
                statLine("Average buy-in", a.averageBuyIn.currencyText)
                statLine("Return on buy-ins", a.roi.formatted(.percent.precision(.fractionLength(1))), color: profitColor(a.roi))
                statLine("Rebuys / add-ons", "\(a.totalRebuys)")
                statLine("Sessions with a rebuy", a.rebuyRate.formatted(.percent.precision(.fractionLength(0))))
            }

            card("Time") {
                statLine("Average session", String(format: "%.1f h", a.averageSessionHours))
                if let longest = a.longestSession { statLine("Longest session", formatDuration(minutes: longest.durationMinutes)) }
                statLine("Sessions per week", a.sessionsPerWeek.formatted(.number.precision(.fractionLength(1))))
                if let best = a.bestMonth { statLine("Best month", "\(monthTitle(best.name)) \(best.profit.signedCurrencyText)", color: StraddleTheme.positive) }
                if let worst = a.worstMonth, worst.profit < 0 { statLine("Worst month", "\(monthTitle(worst.name)) \(worst.profit.signedCurrencyText)", color: StraddleTheme.negative) }
                statLine("Winning months", "\(a.winningMonths) of \(a.byMonth.count)")
            }
        }
    }
}

private func monthTitle(_ key: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM"
    guard let date = formatter.date(from: key) else { return key }
    return date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
}

// MARK: - Bankroll chart

private enum TrendAxis: String, CaseIterable, Identifiable {
    case date = "Date", sessions = "Sessions", hours = "Hours"
    var id: String { rawValue }
}

private struct BankrollChart: View {
    let points: [TrendPoint]
    @State private var axis: TrendAxis = .date
    @State private var selected: TrendPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("X axis", selection: $axis) {
                ForEach(TrendAxis.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if let selected {
                HStack {
                    Text("#\(selected.index) • \(selected.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(StraddleTheme.secondaryText)
                    Spacer()
                    Text(selected.cumulativeProfit.signedCurrencyText).font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(profitColor(selected.cumulativeProfit))
                }
            }

            Chart {
                RuleMark(y: .value("Zero", 0.0)).foregroundStyle(Color.white.opacity(0.2))
                ForEach(points) { point in
                    switch axis {
                    case .date:
                        LineMark(x: .value("Date", point.date), y: .value("Profit", point.cumulativeProfit.doubleValue))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(StraddleTheme.cyan)
                    case .sessions:
                        LineMark(x: .value("Session", point.index), y: .value("Profit", point.cumulativeProfit.doubleValue))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(StraddleTheme.cyan)
                    case .hours:
                        LineMark(x: .value("Hours", point.hours), y: .value("Profit", point.cumulativeProfit.doubleValue))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(StraddleTheme.cyan)
                    }
                }
                if let selected {
                    switch axis {
                    case .date: PointMark(x: .value("Date", selected.date), y: .value("Profit", selected.cumulativeProfit.doubleValue)).foregroundStyle(.white)
                    case .sessions: PointMark(x: .value("Session", selected.index), y: .value("Profit", selected.cumulativeProfit.doubleValue)).foregroundStyle(.white)
                    case .hours: PointMark(x: .value("Hours", selected.hours), y: .value("Profit", selected.cumulativeProfit.doubleValue)).foregroundStyle(.white)
                    }
                }
            }
            .chartYAxis { usdAxis() }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
                    AxisValueLabel().foregroundStyle(StraddleTheme.secondaryText)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let x = value.location.x - geometry[plotFrame].origin.x
                                selected = nearest(to: x, proxy: proxy)
                            }
                            .onEnded { _ in selected = nil })
                }
            }
            .frame(height: 230)
        }
    }

    private func nearest(to x: CGFloat, proxy: ChartProxy) -> TrendPoint? {
        switch axis {
        case .date:
            guard let date: Date = proxy.value(atX: x) else { return nil }
            return points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        case .sessions:
            guard let index: Int = proxy.value(atX: x) else { return nil }
            return points.min { abs($0.index - index) < abs($1.index - index) }
        case .hours:
            guard let hours: Double = proxy.value(atX: x) else { return nil }
            return points.min { abs($0.hours - hours) < abs($1.hours - hours) }
        }
    }
}

// MARK: - Charts

private enum BarMetric: String, CaseIterable, Identifiable {
    case profit = "Profit", hourly = "Hourly", winRate = "Win %"
    var id: String { rawValue }

    func value(_ b: Breakdown) -> Double {
        switch self {
        case .profit: b.profit.doubleValue
        case .hourly: b.hourlyRate.doubleValue
        case .winRate: b.winRate * 100
        }
    }
}

private struct ChartsSection: View {
    let analytics: SessionAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            card("Monthly results") {
                Chart(analytics.byMonth.suffix(18)) { month in
                    BarMark(x: .value("Month", monthTitle(month.name)), y: .value("Profit", month.profit.doubleValue))
                        .foregroundStyle(profitColor(month.profit))
                        .cornerRadius(3)
                }
                .chartYAxis { usdAxis() }
                .chartXAxis {
                    AxisMarks { _ in AxisValueLabel().foregroundStyle(StraddleTheme.secondaryText) }
                }
                .frame(height: 200)
            }

            BreakdownBarCard(title: "By day of week", values: analytics.byWeekday)
            BreakdownBarCard(title: "By time of day", subtitle: "Based on session start time", values: analytics.byTimeOfDay)
            BreakdownBarCard(title: "By session length", values: analytics.byLength)

            card("Session results", subtitle: "How often each result happens") {
                Chart(analytics.resultHistogram) { bin in
                    BarMark(x: .value("Result", bin.mid), y: .value("Sessions", bin.count), width: .ratio(0.9))
                        .foregroundStyle(profitColor(bin.mid))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisValueLabel { if let v = value.as(Double.self) { Text(compactUSD(v)) } }
                            .foregroundStyle(StraddleTheme.secondaryText)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel().foregroundStyle(StraddleTheme.secondaryText)
                    }
                }
                .frame(height: 180)
            }

            HorizontalBreakdownCard(title: "By stakes", values: analytics.byStakes)
            HorizontalBreakdownCard(title: "By venue", values: analytics.byVenue)

            card("Win / loss") {
                Chart {
                    SectorMark(angle: .value("Sessions", analytics.wins), innerRadius: .ratio(0.62), angularInset: 2)
                        .foregroundStyle(StraddleTheme.positive)
                    SectorMark(angle: .value("Sessions", analytics.losses), innerRadius: .ratio(0.62), angularInset: 2)
                        .foregroundStyle(StraddleTheme.negative)
                    SectorMark(angle: .value("Sessions", analytics.sessionCount - analytics.wins - analytics.losses), innerRadius: .ratio(0.62), angularInset: 2)
                        .foregroundStyle(Color.gray)
                }
                .chartBackground { _ in
                    VStack(spacing: 0) {
                        Text(analytics.winRate.formatted(.percent.precision(.fractionLength(0)))).font(.title2.bold())
                        Text("won").font(.caption).foregroundStyle(StraddleTheme.secondaryText)
                    }
                }
                .frame(height: 170)
                HStack(spacing: 16) {
                    Label("\(analytics.wins) won", systemImage: "circle.fill").foregroundStyle(StraddleTheme.positive)
                    Label("\(analytics.losses) lost", systemImage: "circle.fill").foregroundStyle(StraddleTheme.negative)
                }
                .font(.caption)
            }
        }
    }
}

/// Вертикальные столбики для фиксированных групп (дни недели, время суток, длительность).
private struct BreakdownBarCard: View {
    let title: String
    var subtitle: String?
    let values: [Breakdown]
    @State private var metric: BarMetric = .profit

    var body: some View {
        card(title, subtitle: subtitle) {
            Picker("Metric", selection: $metric) {
                ForEach(BarMetric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Chart(values) { item in
                BarMark(x: .value("Group", item.name), y: .value(metric.rawValue, metric.value(item)))
                    .foregroundStyle(metric == .winRate ? StraddleTheme.purple : profitColor(metric.value(item)))
                    .cornerRadius(3)
                    .annotation(position: .top) {
                        if item.sessions > 0 {
                            Text("\(item.sessions)").font(.system(size: 9)).foregroundStyle(StraddleTheme.secondaryText)
                        }
                    }
            }
            .chartYAxis {
                if metric == .winRate {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v))%") } }.foregroundStyle(StraddleTheme.secondaryText)
                    }
                } else {
                    usdAxis()
                }
            }
            .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(StraddleTheme.secondaryText) } }
            .frame(height: 190)
            Text("Number above a bar = sessions played").font(.caption2).foregroundStyle(StraddleTheme.secondaryText)
        }
    }
}

/// Горизонтальные столбики для лимитов / мест.
private struct HorizontalBreakdownCard: View {
    let title: String
    let values: [Breakdown]
    @State private var metric: BarMetric = .profit

    var body: some View {
        let top = Array(values.prefix(8))
        card(title) {
            Picker("Metric", selection: $metric) {
                ForEach(BarMetric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Chart(top) { item in
                BarMark(x: .value(metric.rawValue, metric.value(item)), y: .value("Name", item.name))
                    .foregroundStyle(metric == .winRate ? StraddleTheme.purple : profitColor(metric.value(item)))
                    .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(metric == .winRate ? "\(Int(v))%" : compactUSD(v)) }
                    }
                    .foregroundStyle(StraddleTheme.secondaryText)
                }
            }
            .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(StraddleTheme.secondaryText) } }
            .frame(height: CGFloat(max(2, top.count)) * 36 + 30)
        }
    }
}

// MARK: - Reports

private struct ReportsSection: View {
    let analytics: SessionAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ReportTable(title: "By month", values: analytics.byMonth.reversed(), label: monthTitle)
            if analytics.byYear.count > 1 {
                ReportTable(title: "By year", values: analytics.byYear.reversed())
            }
            ReportTable(title: "By stakes", values: analytics.byStakes)
            ReportTable(title: "By venue", values: analytics.byVenue)
            ReportTable(title: "By game", values: analytics.byGame)
            ReportTable(title: "By day of week", values: analytics.byWeekday.filter { $0.sessions > 0 })
            ReportTable(title: "By time of day", values: analytics.byTimeOfDay.filter { $0.sessions > 0 })
            ReportTable(title: "By session length", values: analytics.byLength.filter { $0.sessions > 0 })
        }
    }
}

private struct ReportTable: View {
    let title: String
    let values: [Breakdown]
    var label: (String) -> String = { $0 }

    var body: some View {
        card(title) {
            ForEach(values) { value in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(label(value.name)).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text("\(value.sessions) sess • \(value.hours.formatted(.number.precision(.fractionLength(1))))h • \(value.hourlyRate.signedCurrencyText)/h • \(value.winRate.formatted(.percent.precision(.fractionLength(0)))) won")
                            .font(.caption).foregroundStyle(StraddleTheme.secondaryText)
                    }
                    Spacer()
                    ProfitText(value: value.profit)
                }
                if value.id != values.last?.id { Divider().overlay(Color.white.opacity(0.08)) }
            }
        }
    }
}

// MARK: - Calendar

private struct ResultsCalendar: View {
    let sessions: [PokerSession]
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
    @State private var selectedDay: Date?

    private let calendar = Calendar.current

    private var byDay: [Date: [PokerSession]] {
        Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.date) }
    }

    private var monthSessions: [PokerSession] {
        sessions.filter { calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    var body: some View {
        let days = byDay
        let monthTotal = monthSessions.reduce(Decimal.zero) { $0 + $1.profit }
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 12) {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    VStack(spacing: 2) {
                        Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                        Text("\(monthSessions.count) sessions • \(monthTotal.signedCurrencyText)")
                            .font(.caption).foregroundStyle(monthSessions.isEmpty ? StraddleTheme.secondaryText : profitColor(monthTotal))
                    }
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.borderless)

                let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(weekdayHeaders.enumerated()), id: \.offset) { Text($0.element).font(.caption2).foregroundStyle(StraddleTheme.secondaryText) }
                    ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                        if let day {
                            dayCell(day, sessions: days[day] ?? [])
                        } else {
                            Color.clear.frame(height: 42)
                        }
                    }
                }
            }
            .straddleCard()

            if let selectedDay, let list = days[selectedDay], !list.isEmpty {
                card(selectedDay.formatted(date: .complete, time: .omitted)) {
                    ForEach(list) { session in
                        SessionRow(session: session)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date, sessions list: [PokerSession]) -> some View {
        let total = list.reduce(Decimal.zero) { $0 + $1.profit }
        let isSelected = selectedDay == day
        return Button {
            selectedDay = isSelected ? nil : day
        } label: {
            VStack(spacing: 1) {
                Text("\(calendar.component(.day, from: day))").font(.caption.weight(.semibold))
                if !list.isEmpty {
                    Text(compactUSD(total.doubleValue)).font(.system(size: 8, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(list.isEmpty ? Color.white.opacity(0.03) : profitColor(total).opacity(0.28))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.white : (calendar.isDateInToday(day) ? StraddleTheme.purple : .clear), lineWidth: 1)
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var weekdayHeaders: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var gridDays: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = calendar.component(.weekday, from: month)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let days: [Date?] = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: leading) + days
    }

    private func shift(_ value: Int) {
        if let next = calendar.date(byAdding: .month, value: value, to: month) {
            month = next
            selectedDay = nil
        }
    }
}
