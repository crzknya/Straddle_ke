import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: SessionStore
    @Binding var sheet: RootSheet?
    @Environment(\.scenePhase) private var scenePhase
    /// Итог за всё время скрыт по умолчанию и снова прячется, когда приложение уходит в фон.
    @State private var profitHidden = true

    private var analytics: SessionAnalytics { AnalyticsEngine.calculate(store.sessions) }
    private var last30: SessionAnalytics { AnalyticsEngine.calculate(AnalyticsEngine.sessions(store.sessions, in: .month)) }

    private var streakText: String {
        let streak = analytics.currentStreak
        if streak == 0 { return "—" }
        return streak > 0 ? "\(streak) W" : "\(-streak) L"
    }

    @ViewBuilder private var liveCard: some View {
        if store.liveSession == nil {
            Button { sheet = .startLive } label: {
                HStack(spacing: 14) {
                    Image(systemName: "play.fill")
                        .font(.title3)
                        .frame(width: 46, height: 46)
                        .background(StraddleTheme.gradient, in: Circle())
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start live session").font(.headline).foregroundStyle(.white)
                        Text("Timer, rebuys and cash-out — nothing to fill in later")
                            .font(.caption).foregroundStyle(StraddleTheme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(StraddleTheme.secondaryText)
                }
                .straddleCard()
            }
            .buttonStyle(.plain)
        }
    }

    var body: some View {
        ZStack {
            StraddleTheme.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    hero
                    liveCard
                    trend
                    quickStats
                    recent
                }
                .padding()
            }
        }
        .navigationTitle("Straddle")
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { profitHidden = true }
        }
        .navigationDestination(for: UUID.self) { id in SessionDetailView(sessionID: id) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AddSessionMenu(sheet: $sheet)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("ALL-TIME PROFIT").font(.caption.weight(.semibold)).tracking(1.3).foregroundStyle(StraddleTheme.secondaryText)
                Spacer()
                Image(systemName: profitHidden ? "eye.slash" : "eye")
                    .font(.subheadline)
                    .foregroundStyle(StraddleTheme.secondaryText)
            }
            Group {
                if profitHidden {
                    Text("••••••")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(StraddleTheme.secondaryText)
                } else {
                    ProfitText(value: analytics.totalProfit, font: .system(size: 42, weight: .bold, design: .rounded))
                }
            }
            .contentTransition(.opacity)
            HStack(spacing: 16) {
                Label("\(analytics.sessionCount) sessions", systemImage: "rectangle.stack")
                Label(String(format: "%.1f hours", analytics.totalHours), systemImage: "clock")
            }
            .font(.caption).foregroundStyle(StraddleTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { profitHidden.toggle() }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(profitHidden ? "Shows all-time profit" : "Hides all-time profit")
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(StraddleTheme.surface)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(StraddleTheme.purple.opacity(0.16)).frame(width: 150).blur(radius: 35).offset(x: 38, y: -55)
                }
        }
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(StraddleTheme.purple.opacity(0.2)) }
    }

    private var trend: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Profit trend").font(.headline).foregroundStyle(.white)
            if analytics.trend.isEmpty {
                EmptyStateView(icon: "chart.xyaxis.line", title: "No trend yet", message: "Log your first session to start tracking.", actionTitle: "Add session") { sheet = .newSession }
            } else {
                ProfitTrendChart(points: analytics.trend)
            }
        }
        .straddleCard()
    }

    private var quickStats: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            MetricCard(title: "Hourly rate", value: analytics.hourlyRate.signedCurrencyText, tint: StraddleTheme.cyan)
            MetricCard(title: "Win rate", value: analytics.winRate.formatted(.percent.precision(.fractionLength(0))), tint: StraddleTheme.purple)
            MetricCard(title: "Last 30 days", value: last30.totalProfit.signedCurrencyText,
                       tint: last30.totalProfit >= 0 ? StraddleTheme.positive : StraddleTheme.negative)
            MetricCard(title: "Streak", value: streakText, tint: analytics.currentStreak >= 0 ? StraddleTheme.positive : StraddleTheme.negative)
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent sessions").font(.headline).foregroundStyle(.white)
                Spacer()
            }
            if store.sessions.isEmpty {
                Text("Your latest sessions will appear here.").font(.subheadline).foregroundStyle(StraddleTheme.secondaryText).padding(.vertical, 10)
            } else {
                ForEach(store.sessions.prefix(5)) { session in
                    NavigationLink(value: session.id) { SessionRow(session: session) }
                        .buttonStyle(.plain)
                    if session.id != store.sessions.prefix(5).last?.id { Divider().overlay(Color.white.opacity(0.08)) }
                }
            }
        }
        .straddleCard()
    }
}
