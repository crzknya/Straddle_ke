import SwiftUI
import Charts

struct ProfitTrendChart: View {
    let points: [TrendPoint]
    var height: CGFloat = 190

    var body: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Date", point.date),
                y: .value("Profit", point.cumulativeProfit.doubleValue)
            )
            .foregroundStyle(LinearGradient(
                colors: [StraddleTheme.purple.opacity(0.35), StraddleTheme.cyan.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
            ))
            LineMark(
                x: .value("Date", point.date),
                y: .value("Profit", point.cumulativeProfit.doubleValue)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(StraddleTheme.cyan)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(StraddleTheme.secondaryText)
                AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount, format: .currency(code: Currency.base).precision(.fractionLength(0)))
                    }
                }
                .foregroundStyle(StraddleTheme.secondaryText)
                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
            }
        }
        .frame(height: height)
        .accessibilityLabel("Cumulative profit trend")
    }
}

struct SessionRow: View {
    let session: PokerSession

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11).fill((session.profit >= 0 ? StraddleTheme.positive : StraddleTheme.negative).opacity(0.14))
                Image(systemName: "suit.spade.fill")
                    .foregroundStyle(session.profit >= 0 ? StraddleTheme.positive : StraddleTheme.negative)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.game).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text("\(session.venue.isEmpty ? "No venue" : session.venue) • \(session.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(StraddleTheme.secondaryText).lineLimit(1)
                Text(detailText)
                    .font(.caption2).foregroundStyle(StraddleTheme.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                ProfitText(value: session.profit)
                if session.isForeignCurrency {
                    Text(session.nativeProfit.currencyText(session.currency, signed: true))
                        .font(.caption2.monospacedDigit()).foregroundStyle(StraddleTheme.secondaryText)
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private var detailText: String {
        var parts = [session.stakes.isEmpty ? session.game : session.stakes,
                     formatDuration(minutes: session.durationMinutes)]
        if session.rebuyCount > 0 {
            parts.append(session.rebuyCount == 1 ? "1 rebuy" : "\(session.rebuyCount) rebuys")
        }
        return parts.joined(separator: " • ")
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(StraddleTheme.gradient)
            Text(title).font(.headline).foregroundStyle(.white)
            Text(message).font(.subheadline).foregroundStyle(StraddleTheme.secondaryText).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}
