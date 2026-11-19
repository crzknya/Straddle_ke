import Foundation

/// Кэш-сессия. Суммы buyIn / cashOut хранятся в валюте игры (`currency`).
/// `exchangeRate` — сколько единиц валюты игры стоит 1 USD (например, 129 KES).
/// Вся статистика считается в долларах через `profit`, `buyInUSD`, `cashOutUSD`.
struct PokerSession: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var game: String
    var stakes: String
    var venue: String
    var buyIn: Decimal
    var cashOut: Decimal
    var durationMinutes: Int
    var notes: String
    var currency: String
    var exchangeRate: Decimal
    var rebuyCount: Int
    var createdAt: Date
    var updatedAt: Date

    static let defaultGame = "No-Limit Hold’em"

    init(
        id: UUID = UUID(),
        date: Date = .now,
        game: String = PokerSession.defaultGame,
        stakes: String = "",
        venue: String = "",
        buyIn: Decimal = 0,
        cashOut: Decimal = 0,
        durationMinutes: Int = 60,
        notes: String = "",
        currency: String = Currency.base,
        exchangeRate: Decimal = 1,
        rebuyCount: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.game = game
        self.stakes = stakes
        self.venue = venue
        self.buyIn = buyIn
        self.cashOut = cashOut
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.currency = currency
        self.exchangeRate = exchangeRate
        self.rebuyCount = rebuyCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, date, game, stakes, venue, buyIn, cashOut, durationMinutes, notes
        case currency, exchangeRate, rebuyCount, createdAt, updatedAt
    }

    /// Декодирование, которое не падает на старых/чужих файлах:
    /// отсутствующие поля получают значения по умолчанию, числа принимаются и строками.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let now = Date.now
        id = c.flexibleUUID(.id) ?? UUID()
        date = (try? c.decodeIfPresent(Date.self, forKey: .date)) ?? now
        game = c.flexibleString(.game) ?? PokerSession.defaultGame
        stakes = c.flexibleString(.stakes) ?? ""
        venue = c.flexibleString(.venue) ?? ""
        buyIn = c.flexibleDecimal(.buyIn) ?? 0
        cashOut = c.flexibleDecimal(.cashOut) ?? 0
        durationMinutes = c.flexibleInt(.durationMinutes) ?? 0
        notes = c.flexibleString(.notes) ?? ""
        let code = (c.flexibleString(.currency) ?? Currency.base).uppercased().trimmingCharacters(in: .whitespaces)
        currency = code.isEmpty ? Currency.base : code
        let rate = c.flexibleDecimal(.exchangeRate) ?? 1
        exchangeRate = (currency == Currency.base || rate <= 0) ? 1 : rate
        rebuyCount = max(0, c.flexibleInt(.rebuyCount) ?? 0)
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? date
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? createdAt
    }

    // MARK: - Native currency

    var nativeProfit: Decimal { cashOut - buyIn }
    var isForeignCurrency: Bool { currency != Currency.base }
    private var safeRate: Decimal { exchangeRate > 0 ? exchangeRate : 1 }

    // MARK: - USD (база всей статистики)

    var buyInUSD: Decimal { Currency.toBase(buyIn, rate: safeRate) }
    var cashOutUSD: Decimal { Currency.toBase(cashOut, rate: safeRate) }
    /// Профит в долларах. Вся аналитика использует именно его.
    var profit: Decimal { Currency.toBase(nativeProfit, rate: safeRate) }

    var durationHours: Double { Double(durationMinutes) / 60 }

    var isValid: Bool {
        buyIn >= 0 && cashOut >= 0 && durationMinutes > 0 && exchangeRate > 0 &&
        !game.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }

    func rounded(_ scale: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}

// MARK: - Tolerant decoding helpers

extension KeyedDecodingContainer {
    func flexibleDecimal(_ key: Key) -> Decimal? {
        if let value = try? decodeIfPresent(Decimal.self, forKey: key) { return value }
        if let text = try? decodeIfPresent(String.self, forKey: key) { return AmountParser.parse(text) }
        return nil
    }

    func flexibleInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value.rounded()) }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return AmountParser.parse(text).map { Int(truncating: NSDecimalNumber(decimal: $0)) }
        }
        return nil
    }

    func flexibleString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        return nil
    }

    func flexibleUUID(_ key: Key) -> UUID? {
        if let value = try? decodeIfPresent(UUID.self, forKey: key) { return value }
        if let text = try? decodeIfPresent(String.self, forKey: key) { return UUID(uuidString: text) }
        return nil
    }
}

enum AmountParser {
    /// "1 500,50" / "1,500.50" / "1500.5" → Decimal. Пусто → nil.
    static func parse(_ text: String) -> Decimal? {
        var cleaned = text.filter { !$0.isWhitespace && $0 != "\u{00A0}" && $0 != "\u{202F}" && $0 != "'" }
        cleaned = cleaned.replacingOccurrences(of: "$", with: "")
        guard !cleaned.isEmpty else { return nil }
        let hasComma = cleaned.contains(",")
        let hasDot = cleaned.contains(".")
        if hasComma && hasDot {
            // Последний разделитель — десятичный, остальные — тысячные.
            let lastComma = cleaned.lastIndex(of: ",")!
            let lastDot = cleaned.lastIndex(of: ".")!
            if lastComma > lastDot {
                cleaned = cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "")
            }
        } else if hasComma {
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        }
        if cleaned.filter({ $0 == "." }).count > 1 { return nil }
        guard cleaned.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Decimal → строка для поля ввода (без группировки, точка как разделитель).
    static func editableText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value.rounded(6)).stringValue
    }
}
