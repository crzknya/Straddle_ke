import SwiftUI
import UIKit

/// Поле суммы на строке, а не на NumberFormatter: значение обновляется сразу при вводе,
/// понимает и запятую, и точку (русская клавиатура ставит запятую).
struct AmountField: View {
    let placeholder: String
    @Binding var value: Decimal?
    @State private var text = ""

    init(_ placeholder: String = "0", value: Binding<Decimal?>) {
        self.placeholder = placeholder
        _value = value
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .onAppear {
                if text.isEmpty, let value { text = AmountParser.editableText(value) }
            }
            .onChange(of: text) { _, newText in
                let parsed = AmountParser.parse(newText)
                if parsed != value { value = parsed }
            }
            .onChange(of: value) { _, newValue in
                guard AmountParser.parse(text) != newValue else { return }
                text = newValue.map(AmountParser.editableText) ?? ""
            }
    }
}

/// Строка "Название ...... [сумма]" + подпись с долларовым эквивалентом.
struct AmountRow: View {
    let title: String
    @Binding var value: Decimal?
    let currency: String
    let rate: Decimal?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                AmountField(value: $value).frame(maxWidth: 170)
                Text(currency).foregroundStyle(StraddleTheme.secondaryText).font(.subheadline)
            }
            if currency != Currency.base, let value, let rate, rate > 0 {
                Text("≈ " + Currency.toBase(value, rate: rate).currencyText)
                    .font(.caption).foregroundStyle(StraddleTheme.secondaryText)
            }
        }
    }
}

/// Выбор валюты игры и курса к доллару.
struct CurrencyRateFields: View {
    @EnvironmentObject private var store: SessionStore
    @Binding var currency: String
    @Binding var rate: Decimal?
    @State private var loading = false
    @State private var fetchError: String?

    var body: some View {
        Picker("Game currency", selection: $currency) {
            ForEach(Currency.all, id: \.self) { code in
                Text(Currency.label(code)).tag(code)
            }
        }
        .pickerStyle(.navigationLink)
        .onChange(of: currency) { _, code in
            rate = store.preferences.rate(for: code)
        }

        if currency != Currency.base {
            HStack {
                Text("1 USD =")
                Spacer()
                AmountField("Rate", value: $rate).frame(maxWidth: 150)
                Text(currency).foregroundStyle(StraddleTheme.secondaryText).font(.subheadline)
            }
            Button {
                Task { await fetchRate() }
            } label: {
                HStack {
                    Label("Load today’s rate (internet)", systemImage: "arrow.down.circle")
                    if loading { Spacer(); ProgressView() }
                }
            }
            .disabled(loading)
            if let fetchError {
                Text(fetchError).font(.caption).foregroundStyle(StraddleTheme.negative)
            } else if rate == nil || rate == 0 {
                Text("Enter how many \(currency) one US dollar costs. All statistics are shown in USD.")
                    .font(.caption).foregroundStyle(StraddleTheme.secondaryText)
            }
        }
    }

    private func fetchRate() async {
        loading = true
        fetchError = nil
        defer { loading = false }
        do {
            rate = try await RateService.usdRate(for: currency)
        } catch {
            fetchError = "Couldn’t load the rate. Enter it manually."
        }
    }
}

/// Текстовое поле с меню ранее использованных значений.
struct SuggestingTextField: View {
    let title: String
    @Binding var text: String
    let suggestions: [String]
    var capitalization: TextInputAutocapitalization = .words

    var body: some View {
        HStack {
            TextField(title, text: $text).textInputAutocapitalization(capitalization)
            if !suggestions.isEmpty {
                Menu {
                    ForEach(suggestions, id: \.self) { value in
                        Button(value) { text = value }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle").foregroundStyle(StraddleTheme.secondaryText)
                }
            }
        }
    }
}

enum RateService {
    /// Курс "единиц валюты за 1 USD" из бесплатного открытого API (без ключа).
    static func usdRate(for code: String) async throws -> Decimal {
        guard code != Currency.base else { return 1 }
        let url = URL(string: "https://open.er-api.com/v6/latest/USD")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: request)
        struct Response: Decodable { let rates: [String: Double] }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let value = response.rates[code], value > 0 else { throw URLError(.cannotParseResponse) }
        return Decimal(string: String(format: "%.4f", value), locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(value)
    }
}

/// Системное окно «Поделиться» для файла.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension View {
    /// Кнопка «Готово» над цифровой клавиатурой (у decimalPad нет Return).
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}

func formatDuration(minutes: Int) -> String {
    let hours = minutes / 60
    let remainder = minutes % 60
    if hours == 0 { return "\(remainder)m" }
    if remainder == 0 { return "\(hours)h" }
    return "\(hours)h \(remainder)m"
}
