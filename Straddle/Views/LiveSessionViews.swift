import SwiftUI

// MARK: - Start

struct StartLiveSessionView: View {
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    let onStarted: () -> Void

    @State private var game: String
    @State private var stakes: String
    @State private var venue: String
    @State private var currency: String
    @State private var rate: Decimal?
    @State private var buyIn: Decimal?
    @State private var startDate = Date.now
    @State private var startedEarlier = false
    @State private var error: String?

    init(template: PokerSession, onStarted: @escaping () -> Void) {
        self.onStarted = onStarted
        _game = State(initialValue: template.game)
        _stakes = State(initialValue: template.stakes)
        _venue = State(initialValue: template.venue)
        _currency = State(initialValue: template.currency)
        _rate = State(initialValue: template.currency == Currency.base ? 1 : (template.exchangeRate > 0 ? template.exchangeRate : nil))
    }

    private var effectiveRate: Decimal { currency == Currency.base ? 1 : (rate ?? 0) }
    private var canStart: Bool {
        effectiveRate > 0 && (buyIn ?? 0) >= 0 && !game.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section("Where") {
                ChoiceField(title: "Venue", text: $venue, options: store.venueOptions, placeholder: "Venue name")
            }
            Section("Game") {
                ChoiceField(title: "Game", text: $game, options: store.recentValues(\.game))
                ChoiceField(title: "Stakes", text: $stakes, options: store.recentValues(\.stakes),
                            placeholder: "Stakes (e.g. 50/100)", capitalization: .never)
            }
            Section("Currency") {
                CurrencyRateFields(currency: $currency, rate: $rate)
            }
            Section {
                AmountRow(title: "Buy-in", value: $buyIn, currency: currency, rate: effectiveRate)
                Toggle("Started earlier", isOn: $startedEarlier)
                if startedEarlier {
                    DatePicker("Start time", selection: $startDate, in: ...Date.now)
                }
            } footer: {
                Text("Rebuys and add-ons can be added while you play.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(StraddleTheme.background)
        .navigationTitle("Start Live Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Start", action: start).fontWeight(.semibold).disabled(!canStart)
            }
        }
        .keyboardDoneButton()
        .alert("Couldn’t Start", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func start() {
        let begin = startedEarlier ? startDate : .now
        var live = LiveSession()
        live.startDate = begin
        live.game = game.trimmingCharacters(in: .whitespacesAndNewlines)
        live.stakes = stakes.trimmingCharacters(in: .whitespacesAndNewlines)
        live.venue = venue.trimmingCharacters(in: .whitespacesAndNewlines)
        live.currency = currency
        live.exchangeRate = effectiveRate
        if let buyIn, buyIn > 0 { live.buyIns = [LiveBuyIn(amount: buyIn, date: begin)] }
        do {
            try store.startLive(live)
            onStarted()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Running session

struct LiveSessionView: View {
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var customAmountPrompt = false
    @State private var customAmountText = ""
    @State private var finishing = false
    @State private var confirmDiscard = false
    @State private var feedback = 0

    var body: some View {
        Group {
            if let live = store.liveSession {
                content(live)
            } else {
                ContentUnavailableView("No live session", systemImage: "stopwatch")
            }
        }
        .background(StraddleTheme.background)
        .navigationTitle("Live Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(role: .destructive) { confirmDiscard = true } label: {
                        Label("Discard session", systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .keyboardDoneButton()
        .sensoryFeedback(.success, trigger: feedback)
        .sheet(isPresented: $finishing) {
            NavigationStack { FinishLiveSessionView() }
        }
        .alert("Add rebuy / add-on", isPresented: $customAmountPrompt) {
            TextField("Amount", text: $customAmountText).keyboardType(.decimalPad)
            Button("Add") {
                if let amount = AmountParser.parse(customAmountText), amount > 0 { addBuyIn(amount) }
                customAmountText = ""
            }
            Button("Cancel", role: .cancel) { customAmountText = "" }
        } message: {
            Text("Amount in \(store.liveSession?.currency ?? Currency.base)")
        }
        .confirmationDialog("Discard this live session? Nothing will be saved.", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { try? store.discardLive() }
        }
    }

    private func content(_ live: LiveSession) -> some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Circle().fill(live.isOnBreak ? Color.orange : StraddleTheme.negative).frame(width: 8, height: 8)
                        Text(live.isOnBreak ? "ON BREAK" : "LIVE").font(.caption.weight(.bold)).tracking(1.2)
                            .foregroundStyle(live.isOnBreak ? Color.orange : StraddleTheme.negative)
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(LiveSession.formatElapsed(live.playedSeconds(at: context.date)))
                            .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    Text("Started \(live.startDate.formatted(date: .omitted, time: .shortened)) • \(live.stakes.isEmpty ? live.game : live.stakes)")
                        .font(.caption).foregroundStyle(StraddleTheme.secondaryText)
                    HStack(spacing: 24) {
                        VStack(spacing: 2) {
                            Text("INVESTED").font(.caption2.weight(.semibold)).foregroundStyle(StraddleTheme.secondaryText)
                            Text(live.totalBuyIn.currencyText(live.currency)).font(.headline.monospacedDigit())
                            if live.currency != Currency.base {
                                Text("≈ " + live.totalBuyInUSD.currencyText).font(.caption2).foregroundStyle(StraddleTheme.secondaryText)
                            }
                        }
                        VStack(spacing: 2) {
                            Text("BUY-INS").font(.caption2.weight(.semibold)).foregroundStyle(StraddleTheme.secondaryText)
                            Text("\(live.buyIns.count)").font(.headline.monospacedDigit())
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                if let last = live.lastBuyInAmount {
                    Button { addBuyIn(last) } label: {
                        Label("Rebuy \(last.currencyText(live.currency))", systemImage: "plus.circle.fill")
                    }
                }
                Button { customAmountPrompt = true } label: {
                    Label(live.buyIns.isEmpty ? "Add buy-in…" : "Rebuy / add-on, other amount…", systemImage: "plus.circle")
                }
                Button {
                    store.updateLive { $0.toggleBreak() }
                } label: {
                    Label(live.isOnBreak ? "Resume play" : "Take a break (pause timer)",
                          systemImage: live.isOnBreak ? "play.fill" : "pause.fill")
                }
                Button {
                    finishing = true
                } label: {
                    Label("Finish session", systemImage: "stop.fill").fontWeight(.semibold)
                }
                .tint(StraddleTheme.negative)
            }

            if !live.buyIns.isEmpty {
                Section("Buy-ins") {
                    ForEach(live.buyIns) { entry in
                        HStack {
                            Text(entry.date.formatted(date: .omitted, time: .shortened)).foregroundStyle(StraddleTheme.secondaryText)
                            Spacer()
                            Text(entry.amount.currencyText(live.currency)).monospacedDigit()
                        }
                    }
                    .onDelete { offsets in
                        store.updateLive { $0.buyIns.remove(atOffsets: offsets) }
                    }
                }
            }

            Section("Details") {
                ChoiceField(title: "Game", text: binding(\.game, live), options: store.recentValues(\.game))
                ChoiceField(title: "Stakes", text: binding(\.stakes, live), options: store.recentValues(\.stakes), capitalization: .never)
                ChoiceField(title: "Venue", text: binding(\.venue, live), options: store.venueOptions, placeholder: "Venue name")
                DatePicker("Start time", selection: binding(\.startDate, live), in: ...Date.now)
                if live.currency != Currency.base {
                    HStack {
                        Text("1 USD =")
                        Spacer()
                        AmountField("Rate", value: Binding(
                            get: { store.liveSession?.exchangeRate },
                            set: { value in if let value, value > 0 { store.updateLive { $0.exchangeRate = value } } }
                        )).frame(maxWidth: 150)
                        Text(live.currency).foregroundStyle(StraddleTheme.secondaryText)
                    }
                }
                TextField("Notes", text: binding(\.notes, live), axis: .vertical).lineLimit(2...6)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<LiveSession, T>, _ fallback: LiveSession) -> Binding<T> {
        Binding(
            get: { (store.liveSession ?? fallback)[keyPath: keyPath] },
            set: { value in store.updateLive { $0[keyPath: keyPath] = value } }
        )
    }

    private func addBuyIn(_ amount: Decimal) {
        store.updateLive { $0.buyIns.append(LiveBuyIn(amount: amount)) }
        feedback += 1
    }
}

// MARK: - Finish

struct FinishLiveSessionView: View {
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var cashOut: Decimal?
    @State private var endDate = Date.now
    @State private var error: String?

    var body: some View {
        Group {
            if let live = store.liveSession {
                form(live)
            } else {
                ContentUnavailableView("Session saved", systemImage: "checkmark.circle")
            }
        }
        .navigationTitle("Finish Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).fontWeight(.semibold).disabled(cashOut == nil)
            }
        }
        .keyboardDoneButton()
        .alert("Couldn’t Save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func form(_ live: LiveSession) -> some View {
        let preview = live.makeSession(cashOut: cashOut ?? 0, endDate: endDate)
        return Form {
            Section {
                AmountRow(title: live."Cash-out", value: $cashOut, currency: live.currency, rate: live.exchangeRate)
            } footer: {
                Text("How many chips you left with. Enter 0 if you busted.")
            }
            Section {
                DatePicker("Ended", selection: $endDate, in: live.startDate...Date.now.addingTimeInterval(60))
            }
            Section("Result") {
                row("Invested", live.totalBuyIn.currencyText(live.currency))
                row("Played", formatDuration(minutes: preview.durationMinutes))
                HStack {
                    Text("Profit").foregroundStyle(StraddleTheme.secondaryText)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        ProfitText(value: preview.profit)
                        if live.currency != Currency.base {
                            Text(preview.nativeProfit.currencyText(live.currency, signed: true))
                                .font(.caption.monospacedDigit()).foregroundStyle(StraddleTheme.secondaryText)
                        }
                    }
                }
                if preview.durationMinutes > 0 {
                    row("Hourly", (preview.profit / Decimal(preview.durationHours)).signedCurrencyText)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(StraddleTheme.background)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(StraddleTheme.secondaryText); Spacer(); Text(value).monospacedDigit() }
    }

    private func save() {
        guard let cashOut else { return }
        do {
            try store.finishLive(cashOut: cashOut, endDate: min(endDate, .now))
            // RootView закроет все окна, как только liveSession станет nil.
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Banner

/// Плашка над таб-баром, пока идёт живая сессия.
struct LiveSessionBanner: View {
    let live: LiveSession

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(live.isOnBreak ? Color.orange : StraddleTheme.negative).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(live.isOnBreak ? "On break" : "Live session")
                    .font(.caption.weight(.semibold)).foregroundStyle(StraddleTheme.secondaryText)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(LiveSession.formatElapsed(live.playedSeconds(at: context.date)))
                        .font(.headline.monospacedDigit()).foregroundStyle(.white)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("In for").font(.caption2).foregroundStyle(StraddleTheme.secondaryText)
                Text(live.totalBuyIn.currencyText(live.currency)).font(.subheadline.weight(.semibold).monospacedDigit())
            }
            Image(systemName: "chevron.up").foregroundStyle(StraddleTheme.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(StraddleTheme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(StraddleTheme.purple.opacity(0.45)) }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
    }
}
