import Foundation

struct LiveBuyIn: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var amount: Decimal
    var date: Date = .now
}

/// «Живая» сессия, идущая прямо сейчас. Хранится на диске отдельно,
/// поэтому переживает закрытие/перезапуск приложения.
struct LiveSession: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var startDate: Date = .now
    var type: SessionType = .cash
    var game: String = PokerSession.defaultGame
    var stakes: String = ""
    var venue: String = ""
    var currency: String = Currency.base
    var exchangeRate: Decimal = 1
    var buyIns: [LiveBuyIn] = []
    var notes: String = ""
    /// Если не nil — сейчас перерыв, начавшийся в это время.
    var breakStartedAt: Date?
    /// Сумма завершённых перерывов, в секундах.
    var pausedSeconds: TimeInterval = 0

    var totalBuyIn: Decimal { buyIns.reduce(Decimal.zero) { $0 + $1.amount } }
    var totalBuyInUSD: Decimal { Currency.toBase(totalBuyIn, rate: exchangeRate) }
    var isOnBreak: Bool { breakStartedAt != nil }
    var lastBuyInAmount: Decimal? { buyIns.last?.amount }

    /// Чистое игровое время (без перерывов).
    func playedSeconds(at now: Date = .now) -> TimeInterval {
        let currentBreak = breakStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        return max(0, now.timeIntervalSince(startDate) - pausedSeconds - currentBreak)
    }

    mutating func toggleBreak(now: Date = .now) {
        if let started = breakStartedAt {
            pausedSeconds += max(0, now.timeIntervalSince(started))
            breakStartedAt = nil
        } else {
            breakStartedAt = now
        }
    }

    func makeSession(cashOut: Decimal, endDate: Date, notes extraNotes: String? = nil) -> PokerSession {
        let end = max(endDate, startDate)
        let minutes = max(1, Int((playedSeconds(at: end) / 60).rounded()))
        let text = (extraNotes ?? notes).trimmingCharacters(in: .whitespacesAndNewlines)
        return PokerSession(
            id: id,
            date: startDate,
            type: type,
            game: game.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? PokerSession.defaultGame : game.trimmingCharacters(in: .whitespacesAndNewlines),
            stakes: stakes.trimmingCharacters(in: .whitespacesAndNewlines),
            venue: venue.trimmingCharacters(in: .whitespacesAndNewlines),
            buyIn: totalBuyIn,
            cashOut: cashOut,
            durationMinutes: minutes,
            notes: text,
            currency: currency,
            exchangeRate: currency == Currency.base ? 1 : exchangeRate,
            rebuyCount: max(0, buyIns.count - 1),
            createdAt: .now,
            updatedAt: .now
        )
    }

    static func formatElapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
