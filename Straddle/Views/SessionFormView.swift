import SwiftUI

struct SessionFormView: View {
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss

    private let original: PokerSession?
    @State private var date: Date
    @State private var game: String
    @State private var stakes: String
    @State private var venue: String
    @State private var currency: String
    @State private var rate: Decimal?
    @State private var buyIn: Decimal?
    @State private var rebuyCount: Int
    @State private var cashOut: Decimal?
    @State private var hours: Int
    @State private var minutes: Int
    @State private var notes: String
    @State private var saveError: String?

    /// - Parameters:
    ///   - session: существующая сессия для редактирования.
    ///   - template: заготовка для новой сессии (игра/место/валюта из прошлого раза).
    init(session: PokerSession? = nil, template: PokerSession? = nil) {
        original = session
        let source = session ?? template
        _date = State(initialValue: session?.date ?? .now)
        _game = State(initialValue: source?.game ?? PokerSession.defaultGame)
        _stakes = State(initialValue: source?.stakes ?? "")
        _venue = State(initialValue: source?.venue ?? "")
        let code = source?.currency ?? Currency.base
        _currency = State(initialValue: code)
        let sourceRate = source?.exchangeRate ?? 1
        _rate = State(initialValue: code == Currency.base ? 1 : (sourceRate > 0 ? sourceRate : nil))
        _buyIn = State(initialValue: session?.buyIn)
        _rebuyCount = State(initialValue: session?.rebuyCount ?? 0)
        _cashOut = State(initialValue: session?.cashOut)
        _hours = State(initialValue: (session?.durationMinutes ?? 180) / 60)
        _minutes = State(initialValue: (session?.durationMinutes ?? 180) % 60)
        _notes = State(initialValue: session?.notes ?? "")
    }

    private var effectiveRate: Decimal { currency == Currency.base ? 1 : (rate ?? 0) }

    private var draft: PokerSession {
        PokerSession(
            id: original?.id ?? UUID(),
            date: date,
            game: game.trimmingCharacters(in: .whitespacesAndNewlines),
            stakes: stakes.trimmingCharacters(in: .whitespacesAndNewlines),
            venue: venue.trimmingCharacters(in: .whitespacesAndNewlines),
            buyIn: buyIn ?? 0,
            cashOut: cashOut ?? 0,
            durationMinutes: hours * 60 + minutes,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            currency: currency,
            exchangeRate: effectiveRate,
            rebuyCount: rebuyCount,
            createdAt: original?.createdAt ?? .now,
            updatedAt: .now
        )
    }

    private var validationMessage: String? {
        if game.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter the game." }
        if effectiveRate <= 0 { return "Enter the exchange rate for \(currency)." }
        if hours * 60 + minutes <= 0 { return "Duration must be longer than 0 minutes." }
        if (buyIn ?? 0) < 0 || (cashOut ?? 0) < 0 { return "Amounts can’t be negative." }
        return nil
    }

    var body: some View {
        Form {
            Section("When & where") {
                DatePicker("Started", selection: $date, in: ...Date.now)
                ChoiceField(title: "Venue", text: $venue, options: store.venueOptions, placeholder: "Venue name")
            }

            Section("Game") {
                ChoiceField(title: "Game", text: $game, options: store.recentValues(\.game), placeholder: "Game (e.g. No-Limit Hold’em)")
                ChoiceField(title: "Stakes", text: $stakes, options: store.recentValues(\.stakes),
                            placeholder: "Stakes (e.g. 50/100)", capitalization: .never)
            }

            Section {
                CurrencyRateFields(currency: $currency, rate: $rate)
            } header: {
                Text("Currency")
            } footer: {
                Text("Amounts are entered in the game currency and converted to USD for all statistics.")
            }

            Section("Results") {
                AmountRow(title: "Total buy-in", value: $buyIn, currency: currency, rate: effectiveRate)
                Stepper("Rebuys / add-ons: \(rebuyCount)", value: $rebuyCount, in: 0...99)
                AmountRow(title: "Cash-out", value: $cashOut, currency: currency, rate: effectiveRate)
                HStack {
                    Text("Profit")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        ProfitText(value: draft.profit)
                        if currency != Currency.base {
                            Text(draft.nativeProfit.currencyText(currency, signed: true))
                                .font(.caption.monospacedDigit()).foregroundStyle(StraddleTheme.secondaryText)
                        }
                    }
                }
            }

            Section("Duration") {
                Stepper("Hours: \(hours)", value: $hours, in: 0...72)
                Stepper("Minutes: \(minutes)", value: $minutes, in: 0...59, step: 5)
            }

            Section("Notes (optional)") {
                TextField("Table, lineup, key hands…", text: $notes, axis: .vertical).lineLimit(3...7)
            }

            if let validationMessage {
                Section { Text(validationMessage).font(.footnote).foregroundStyle(StraddleTheme.negative) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(StraddleTheme.background)
        .navigationTitle(original == nil ? "New Session" : "Edit Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).fontWeight(.semibold).disabled(validationMessage != nil)
            }
        }
        .keyboardDoneButton()
        .alert("Couldn’t Save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: { Text(saveError ?? "Unknown error") }
    }

    private func save() {
        do {
            let value = draft
            try store.upsert(value)
            store.rememberVenue(value.venue)
            store.rememberCurrency(value.currency, rate: value.exchangeRate)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
