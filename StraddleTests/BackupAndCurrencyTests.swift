import XCTest
@testable import Straddle

@MainActor
final class BackupAndCurrencyTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StraddleBackupTests-\(UUID().uuidString)", isDirectory: true)
        suiteName = "StraddleTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStore(_ name: String = "sessions.json") -> SessionStore {
        SessionStore(fileURL: directory.appendingPathComponent(name), defaults: defaults)
    }

    func testProfitIsConvertedToUSD() {
        let session = PokerSession(buyIn: 10_000, cashOut: 23_000, currency: "EUR", exchangeRate: 130)
        XCTAssertEqual(session.nativeProfit, 13_000)
        XCTAssertEqual(session.profit, 100)
        XCTAssertEqual(session.buyInUSD.rounded(2), Decimal(string: "76.92"))
        let analytics = AnalyticsEngine.calculate([session, PokerSession(buyIn: 100, cashOut: 50)])
        XCTAssertEqual(analytics.totalProfit, 50)
    }

    func testLegacySessionsJSONDecodesWithDefaults() throws {
        let legacy = """
        [{"id":"5C6F2A0E-1111-4F6B-9E36-2D9F1E7A0001","date":750000000,"type":"Cash Game","game":"NLH",
          "stakes":"1/2","venue":"Home","buyIn":200,"cashOut":350,"durationMinutes":120,"notes":"",
          "createdAt":750000000,"updatedAt":750000000}]
        """
        let parsed = try SessionStore.parseBackup(Data(legacy.utf8))
        XCTAssertEqual(parsed.sessions.count, 1)
        XCTAssertEqual(parsed.sessions[0].currency, "USD")
        XCTAssertEqual(parsed.sessions[0].exchangeRate, 1)
        XCTAssertEqual(parsed.sessions[0].profit, 150)
    }

    func testTolerantParsingSkipsBrokenEntriesAndAcceptsStrings() throws {
        let json = """
        {"sessions":[
          {"date":"2025-03-01T20:00:00Z","type":"tournament","buyIn":"1 500,5","cashOut":0,"durationMinutes":"90"},
          "garbage",
          {"date":"2025-03-02","buyIn":100,"cashOut":100}
        ]}
        """
        let parsed = try SessionStore.parseBackup(Data(("\u{FEFF}" + json).utf8))
        XCTAssertEqual(parsed.sessions.count, 2)
        XCTAssertEqual(parsed.skipped, 1)
        XCTAssertEqual(parsed.sessions[0].buyIn, Decimal(string: "1500.5"))
        XCTAssertEqual(parsed.sessions[0].durationMinutes, 90)
    }

    func testBackupRoundTripOnFreshInstall() throws {
        let store = makeStore()
        try store.upsert(PokerSession(venue: "Club", buyIn: 5_000, cashOut: 9_000, currency: "EUR", exchangeRate: 129))
        try store.upsert(PokerSession(venue: "Home", buyIn: 100, cashOut: 40))
        store.rememberCurrency("EUR", rate: 129)
        let data = try store.backupData()

        // «Переустановка»: новый пустой файл и чистые настройки.
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        let fresh = makeStore()
        XCTAssertTrue(fresh.sessions.isEmpty)

        let file = directory.appendingPathComponent("import.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file)
        let preview = try fresh.prepareImport(from: file)
        XCTAssertEqual(preview.newCount, 2)
        try fresh.applyImport(preview, replace: false)

        XCTAssertEqual(Set(fresh.sessions.map(\.id)), Set(store.sessions.map(\.id)))
        XCTAssertEqual(fresh.sessions.map(\.profit).reduce(0, +), store.sessions.map(\.profit).reduce(0, +))
        XCTAssertEqual(fresh.preferences.rates["EUR"], 129)

        // Повторный импорт не создаёт дублей.
        try fresh.applyImport(try fresh.prepareImport(from: file), replace: false)
        XCTAssertEqual(fresh.sessions.count, 2)
    }

    func testLiveSessionFlow() throws {
        let store = makeStore()
        var live = LiveSession()
        live.startDate = Date.now.addingTimeInterval(-3 * 3600)
        live.currency = "EUR"
        live.exchangeRate = 100
        live.buyIns = [LiveBuyIn(amount: 10_000, date: live.startDate)]
        try store.startLive(live)
        store.updateLive { $0.buyIns.append(LiveBuyIn(amount: 5_000)) }

        // Переживает перезапуск приложения.
        let reopened = makeStore()
        XCTAssertEqual(reopened.liveSession?.totalBuyIn, 15_000)

        let saved = try reopened.finishLive(cashOut: 25_000, endDate: .now)
        XCTAssertNil(reopened.liveSession)
        XCTAssertEqual(saved.buyIn, 15_000)
        XCTAssertEqual(saved.rebuyCount, 1)
        XCTAssertEqual(saved.profit, 100)
        XCTAssertEqual(saved.durationMinutes, 180, accuracy: 1)
        XCTAssertEqual(reopened.sessions.count, 1)
        XCTAssertNil(makeStore().liveSession)
    }

    func testBreaksAreExcludedFromDuration() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var live = LiveSession()
        live.startDate = start
        live.toggleBreak(now: start.addingTimeInterval(3600))
        live.toggleBreak(now: start.addingTimeInterval(3600 + 1800))
        let session = live.makeSession(cashOut: 0, endDate: start.addingTimeInterval(2 * 3600))
        XCTAssertEqual(session.durationMinutes, 90)
    }

    func testAssignCurrencyToLegacySessions() throws {
        let store = makeStore()
        try store.upsert(PokerSession(buyIn: 10_000, cashOut: 15_000))
        try store.upsert(PokerSession(buyIn: 100, cashOut: 200, currency: "EUR", exchangeRate: 0.5))
        try store.assignCurrencyToUSDSessions("EUR", rate: 125)
        XCTAssertEqual(store.usdSessionCount, 0)
        XCTAssertEqual(store.sessions.map(\.profit).reduce(0, +), 40 + 200)
        XCTAssertEqual(store.preferences.rates["EUR"], 125)
    }

    func testAmountParser() {
        XCTAssertEqual(AmountParser.parse("1 234,56"), Decimal(string: "1234.56"))
        XCTAssertEqual(AmountParser.parse("1,234.56"), Decimal(string: "1234.56"))
        XCTAssertEqual(AmountParser.parse("129,5"), Decimal(string: "129.5"))
        XCTAssertNil(AmountParser.parse(""))
        XCTAssertNil(AmountParser.parse("12abc"))
    }
}
