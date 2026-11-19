import Foundation

enum Currency {
    /// Базовая валюта всей статистики.
    static let base = "USD"

    /// Валюты, которые показываются первыми в списке.
    static let favorites = ["USD", "KES", "EUR", "GBP", "RUB", "UAH", "KZT", "AED", "TZS", "UGX", "ZAR", "THB"]

    static let all: [String] = {
        let common = Set(Locale.commonISOCurrencyCodes)
        let rest = common.subtracting(favorites).sorted()
        return favorites + rest
    }()

    static func name(_ code: String) -> String {
        Locale(identifier: "en_US").localizedString(forCurrencyCode: code) ?? code
    }

    static func label(_ code: String) -> String { "\(code) — \(name(code))" }

    /// Сумма в валюте игры → USD. `rate` = единиц валюты за 1 USD.
    static func toBase(_ amount: Decimal, rate: Decimal) -> Decimal {
        guard rate > 0 else { return amount }
        return amount / rate
    }

    static func format(_ value: Decimal, code: String, signed: Bool = false, fractionDigits: Int? = nil) -> String {
        let digits = fractionDigits ?? (code == base ? 2 : (abs(value.doubleValue) >= 1000 ? 0 : 2))
        var style = Decimal.FormatStyle.Currency(code: code).precision(.fractionLength(digits))
        if signed { style = style.sign(strategy: .always()) }
        return value.formatted(style)
    }
}

extension Decimal {
    /// Всегда в долларах.
    var currencyText: String { Currency.format(self, code: Currency.base) }
    var signedCurrencyText: String { Currency.format(self, code: Currency.base, signed: true) }

    func currencyText(_ code: String, signed: Bool = false) -> String {
        Currency.format(self, code: code, signed: signed)
    }
}
