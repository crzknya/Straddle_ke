import XCTest
@testable import Straddle

final class AnalyticsEngineTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testCoreMetricsAndTrend() throws {
        let firstDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 1, day: 1)))
        let secondDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 1, day: 2)))
        let thirdDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 1, day: 3)))
        let sessions = [
            make(date: secondDate, game: "PLO", venue: "Bellagio", buyIn: 500, cashOut: 300, minutes: 120),
            make(date: firstDate, game: "NLH", venue: "Aria", buyIn: 200, cashOut: 500, minutes: 180),
            make(date: thirdDate, game: "NLH", venue: "Aria", buyIn: 100, cashOut: 400, minutes: 300)
        ]

        let result = AnalyticsEngine.calculate(sessions)

        XCTAssertEqual(result.totalProfit, 400)
        XCTAssertEqual(result.totalHours, 10, accuracy: 0.0001)
        XCTAssertEqual(result.hourlyRate, 40)
        XCTAssertEqual(result.sessionCount, 3)
        XCTAssertEqual(result.wins, 2)
        XCTAssertEqual(result.winRate, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(result.averageWin, 300)
        XCTAssertEqual(result.averageLoss, -200)
        XCTAssertEqual(result.bestSession?.profit, 300)
        XCTAssertEqual(result.worstSession?.profit, -200)
        XCTAssertEqual(result.totalBuyIn, 800)
        XCTAssertEqual(result.roi, 0.5, accuracy: 0.0001)
        XCTAssertEqual(result.maxDrawdown, 200)
        XCTAssertEqual(result.peakProfit, 400)
        XCTAssertEqual(result.longestWinStreak, 1)
        XCTAssertEqual(result.currentStreak, 1)
        XCTAssertEqual(result.trend.map(\.index), [1, 2, 3])
        XCTAssertEqual(result.trend.map(\.cumulativeProfit), [300, 100, 400])
    }

    func testBreakdownsAggregateAndSortByProfit() {
        let sessions = [
            make(game: "NLH", venue: "Home", buyIn: 100, cashOut: 250, minutes: 60),
            make(game: "NLH", venue: "Home", buyIn: 100, cashOut: 50, minutes: 60),
            make(game: "PLO", venue: "Club", buyIn: 100, cashOut: 120, minutes: 30)
        ]
        let result = AnalyticsEngine.calculate(sessions)

        XCTAssertEqual(result.byVenue.map(\.name), ["Home", "Club"])
        XCTAssertEqual(result.byVenue.first?.profit, 100)
        XCTAssertEqual(result.byVenue.first?.sessions, 2)
        XCTAssertEqual(result.byVenue.first?.hourlyRate, 50)
        XCTAssertEqual(result.byGame.map(\.name), ["NLH", "PLO"])
    }

    func testEmptyAnalyticsAreSafe() {
        let result = AnalyticsEngine.calculate([])
        XCTAssertEqual(result.totalProfit, 0)
        XCTAssertEqual(result.hourlyRate, 0)
        XCTAssertEqual(result.winRate, 0)
        XCTAssertEqual(result.roi, 0)
        XCTAssertNil(result.bigBlindsPerHour)
        XCTAssertTrue(result.resultHistogram.isEmpty)
        XCTAssertNil(result.bestSession)
        XCTAssertTrue(result.trend.isEmpty)
    }

    func testRangeFiltering() throws {
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 6, day: 30)))
        let recent = make(date: try XCTUnwrap(calendar.date(byAdding: .day, value: -5, to: now)))
        let old = make(date: try XCTUnwrap(calendar.date(byAdding: .day, value: -100, to: now)))
        XCTAssertEqual(AnalyticsEngine.sessions([recent, old], in: .month, now: now, calendar: calendar).map(\.id), [recent.id])
        XCTAssertEqual(AnalyticsEngine.sessions([recent, old], in: .all, now: now, calendar: calendar).count, 2)
    }

    func testBigBlindsPerHourAndVariance() {
        let sessions = [
            make(buyIn: 10_000, cashOut: 20_000, minutes: 120, stakes: "50/100"),   // +100 BB за 2 ч
            make(buyIn: 10_000, cashOut: 5_000, minutes: 180, stakes: "50/100")     // −50 BB за 3 ч
        ]
        let result = AnalyticsEngine.calculate(sessions)
        XCTAssertEqual(result.bigBlindsWon ?? 0, 50, accuracy: 0.0001)
        XCTAssertEqual(result.bigBlindsPerHour ?? 0, 10, accuracy: 0.0001)
        XCTAssertGreaterThan(result.standardDeviation, 0)
        XCTAssertGreaterThan(result.standardDeviationPerHour, 0)
        XCTAssertEqual(result.resultHistogram.map(\.count).reduce(0, +), 2)
    }

    func testStakesParser() {
        XCTAssertEqual(StakesParser.bigBlind("50/100"), 100)
        XCTAssertEqual(StakesParser.bigBlind("$1/$2"), 2)
        XCTAssertEqual(StakesParser.bigBlind("100/200/400"), 200)
        XCTAssertNil(StakesParser.bigBlind("Home game"))
    }

    func testWeekdayBreakdownStartsMonday() {
        let result = AnalyticsEngine.calculate([make()])
        XCTAssertEqual(result.byWeekday.count, 7)
        XCTAssertEqual(result.byWeekday.map(\.sessions).reduce(0, +), 1)
        XCTAssertEqual(result.byTimeOfDay.map(\.sessions).reduce(0, +), 1)
    }

    private func make(
        date: Date = .now,
        game: String = "NLH",
        venue: String = "Aria",
        buyIn: Decimal = 100,
        cashOut: Decimal = 200,
        minutes: Int = 60,
        stakes: String = "1/2"
    ) -> PokerSession {
        PokerSession(date: date, game: game, stakes: stakes, venue: venue, buyIn: buyIn, cashOut: cashOut, durationMinutes: minutes)
    }
}
