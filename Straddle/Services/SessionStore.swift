import Combine
import Foundation

enum StoreError: LocalizedError, Equatable {
    case createDirectory(String)
    case encode(String)
    case write(String)
    case read(String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .createDirectory(let message): "Could not create local storage: \(message)"
        case .encode(let message): "Could not encode sessions: \(message)"
        case .write(let message): "Could not save sessions: \(message)"
        case .read(let message): "Could not read file: \(message)"
        case .decode(let message): "The file is not a valid Straddle backup: \(message)"
        }
    }
}

/// Настройки, которые запоминаются между сессиями и попадают в бэкап.
struct Preferences: Codable, Equatable, Sendable {
    /// Валюта игры по умолчанию для новых сессий (последняя использованная).
    var defaultCurrency: String = Currency.base
    /// Последний введённый курс для каждой валюты: единиц за 1 USD.
    var rates: [String: Decimal] = [:]
    var lastBackupAt: Date?

    init() {}

    enum CodingKeys: String, CodingKey { case defaultCurrency, rates, lastBackupAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultCurrency = c.flexibleString(.defaultCurrency) ?? Currency.base
        rates = (try? c.decodeIfPresent([String: Decimal].self, forKey: .rates)) ?? [:]
        lastBackupAt = try? c.decodeIfPresent(Date.self, forKey: .lastBackupAt)
    }

    func rate(for code: String) -> Decimal? {
        code == Currency.base ? 1 : rates[code]
    }
}

/// Результат разбора файла импорта — показывается пользователю перед применением.
struct ImportPreview: Identifiable {
    let id = UUID()
    let fileName: String
    let sessions: [PokerSession]
    let preferences: Preferences?
    let liveSession: LiveSession?
    let skipped: Int
    let newCount: Int
    let updatedCount: Int
}

/// JSON-кодирование вне MainActor, чтобы его можно было звать откуда угодно.
enum StraddleCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        return encoder
    }

    /// Даты принимаются в любом разумном виде: число (reference date или unix),
    /// ISO-8601 строка, "yyyy-MM-dd".
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                // > 1.2e9 — это unix-время (reference-время дойдёт до таких чисел лишь в 2039).
                return number > 1_200_000_000
                    ? Date(timeIntervalSince1970: number > 100_000_000_000 ? number / 1000 : number)
                    : Date(timeIntervalSinceReferenceDate: number)
            }
            let text = try container.decode(String.self)
            if let date = StraddleCoding.parseDate(text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(text)")
        }
        return decoder
    }

    static func parseDate(_ text: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "dd.MM.yyyy HH:mm", "dd.MM.yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        if let number = Double(text) { return Date(timeIntervalSince1970: number) }
        return nil
    }
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [PokerSession] = []
    @Published private(set) var liveSession: LiveSession?
    @Published private(set) var preferences = Preferences()
    @Published var lastError: StoreError?

    let fileURL: URL
    var liveFileURL: URL { fileURL.deletingLastPathComponent().appendingPathComponent("live-session.json") }

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private static let preferencesKey = "straddle.preferences.v1"

    init(fileURL: URL? = nil,
         fileManager: FileManager = .default,
         defaults: UserDefaults = .standard,
         loadImmediately: Bool = true) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.fileURL = fileURL ?? Self.resolvedFileURL(fileManager: fileManager)
        if loadImmediately { load() }
    }

    // MARK: - Storage location

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let root = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("sessions.json")
    }

    static func legacyFileURL(fileManager: FileManager = .default) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("Straddle", isDirectory: true)
            .appendingPathComponent("sessions.json")
    }

    /// Documents виден в «Файлах». Если там пусто, а старый файл есть — переносим.
    /// Если перенести не удалось, читаем старый путь, чтобы ничего не потерять.
    static func resolvedFileURL(fileManager: FileManager = .default) -> URL {
        let modern = defaultFileURL(fileManager: fileManager)
        if fileManager.fileExists(atPath: modern.path) { return modern }
        let legacy = legacyFileURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: legacy.path) else { return modern }
        do {
            try fileManager.createDirectory(at: modern.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try fileManager.copyItem(at: legacy, to: modern)
            return modern
        } catch {
            return legacy
        }
    }

    // MARK: - Load

    func load() {
        loadPreferences()
        loadLiveSession()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            sessions = []
            lastError = nil
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let parsed = try Self.parseBackup(data)
            sessions = Self.deduplicated(parsed.sessions).sorted(by: Self.newestFirst)
            lastError = nil
        } catch {
            // Файл не читается — откладываем копию, чтобы следующее сохранение его не затёрло.
            preserveUnreadableFile()
            sessions = []
            lastError = .decode("\(error.localizedDescription). A copy of the original file was kept in the Straddle folder in Files.")
        }
    }

    private func preserveUnreadableFile() {
        let stamp = Int(Date.now.timeIntervalSince1970)
        let copy = fileURL.deletingLastPathComponent().appendingPathComponent("sessions-unreadable-\(stamp).json")
        try? fileManager.copyItem(at: fileURL, to: copy)
    }

    private func loadPreferences() {
        guard let data = defaults.data(forKey: Self.preferencesKey),
              let value = try? StraddleCoding.makeDecoder().decode(Preferences.self, from: data) else {
            preferences = Preferences()
            return
        }
        preferences = value
    }

    private func loadLiveSession() {
        guard fileManager.fileExists(atPath: liveFileURL.path),
              let data = try? Data(contentsOf: liveFileURL) else {
            liveSession = nil
            return
        }
        liveSession = try? StraddleCoding.makeDecoder().decode(LiveSession.self, from: data)
    }

    // MARK: - Sessions CRUD

    @discardableResult
    func upsert(_ session: PokerSession) throws -> PokerSession {
        var value = session
        value.updatedAt = .now
        var next = sessions
        if let index = next.firstIndex(where: { $0.id == value.id }) {
            next[index] = value
        } else {
            next.append(value)
        }
        try commit(next)
        return value
    }

    func delete(id: UUID) throws {
        try commit(sessions.filter { $0.id != id })
    }

    func delete(at offsets: IndexSet, from visibleSessions: [PokerSession]) throws {
        let ids = Set(offsets.compactMap { visibleSessions.indices.contains($0) ? visibleSessions[$0].id : nil })
        try commit(sessions.filter { !ids.contains($0.id) })
    }

    func replaceAll(_ values: [PokerSession]) throws {
        try commit(Self.deduplicated(values))
    }

    /// Объединяет по id. При конфликте побеждает более свежий updatedAt.
    func merge(_ incoming: [PokerSession]) throws {
        try commit(Self.merged(existing: sessions, incoming: incoming))
    }

    static func merged(existing: [PokerSession], incoming: [PokerSession]) -> [PokerSession] {
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.updatedAt >= b.updatedAt ? a : b })
        for session in incoming {
            if let current = byID[session.id], current.updatedAt > session.updatedAt { continue }
            byID[session.id] = session
        }
        return Array(byID.values)
    }

    private static func deduplicated(_ values: [PokerSession]) -> [PokerSession] {
        merged(existing: [], incoming: values)
    }

    private static func newestFirst(_ a: PokerSession, _ b: PokerSession) -> Bool {
        if a.date == b.date { return a.createdAt > b.createdAt }
        return a.date > b.date
    }

    private func commit(_ values: [PokerSession]) throws {
        let sorted = values.sorted(by: Self.newestFirst)
        do {
            try write(sorted, to: fileURL)
            sessions = sorted
            lastError = nil
        } catch {
            let storeError = error as? StoreError ?? .write(error.localizedDescription)
            lastError = storeError
            throw storeError
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        do { try fileManager.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { throw StoreError.createDirectory(error.localizedDescription) }
        let data: Data
        do { data = try StraddleCoding.makeEncoder().encode(value) }
        catch { throw StoreError.encode(error.localizedDescription) }
        do { try data.write(to: url, options: .atomic) }
        catch { throw StoreError.write(error.localizedDescription) }
    }

    // MARK: - Preferences

    func updatePreferences(_ mutate: (inout Preferences) -> Void) {
        var value = preferences
        mutate(&value)
        preferences = value
        if let data = try? StraddleCoding.makeEncoder().encode(value) {
            defaults.set(data, forKey: Self.preferencesKey)
        }
    }

    /// Запоминает валюту и курс, чтобы подставлять их в следующий раз.
    func rememberCurrency(_ code: String, rate: Decimal) {
        updatePreferences { prefs in
            prefs.defaultCurrency = code
            if code != Currency.base, rate > 0 { prefs.rates[code] = rate }
        }
    }

    /// Шаблон для новой сессии: игра/лимит/место из последней сессии, валюта и курс из настроек.
    func newSessionTemplate() -> PokerSession {
        let last = sessions.max { $0.createdAt < $1.createdAt }
        let code = preferences.defaultCurrency
        return PokerSession(
            type: last?.type ?? .cash,
            game: last?.game ?? PokerSession.defaultGame,
            stakes: last?.stakes ?? "",
            venue: last?.venue ?? "",
            currency: code,
            exchangeRate: preferences.rate(for: code) ?? 0
        )
    }

    /// Ранее использованные значения для подсказок в формах.
    func recentValues(_ keyPath: KeyPath<PokerSession, String>, limit: Int = 8) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for session in sessions.sorted(by: { $0.createdAt > $1.createdAt }) {
            let value = session[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value.lowercased()).inserted else { continue }
            result.append(value)
            if result.count == limit { break }
        }
        return result
    }

    // MARK: - Live session

    func startLive(_ live: LiveSession) throws {
        try persistLive(live)
        rememberCurrency(live.currency, rate: live.exchangeRate)
    }

    func updateLive(_ mutate: (inout LiveSession) -> Void) {
        guard var value = liveSession else { return }
        mutate(&value)
        do { try persistLive(value) }
        catch { lastError = error as? StoreError ?? .write(error.localizedDescription) }
    }

    @discardableResult
    func finishLive(cashOut: Decimal, endDate: Date) throws -> PokerSession {
        guard let live = liveSession else { throw StoreError.write("No live session is running") }
        let saved = try upsert(live.makeSession(cashOut: cashOut, endDate: endDate))
        rememberCurrency(live.currency, rate: live.exchangeRate)
        try persistLive(nil)
        return saved
    }

    func discardLive() throws {
        try persistLive(nil)
    }

    private func persistLive(_ value: LiveSession?) throws {
        if let value {
            try write(value, to: liveFileURL)
        } else if fileManager.fileExists(atPath: liveFileURL.path) {
            do { try fileManager.removeItem(at: liveFileURL) }
            catch { throw StoreError.write(error.localizedDescription) }
        }
        liveSession = value
    }

    // MARK: - Backup / transfer

    struct Backup: Codable {
        var format = "straddle-backup"
        var version = 2
        var exportedAt: Date
        var appVersion: String?
        var preferences: Preferences?
        var liveSession: LiveSession?
        var sessions: [PokerSession]
    }

    struct ParsedBackup {
        var sessions: [PokerSession]
        var preferences: Preferences?
        var liveSession: LiveSession?
        var skipped: Int
    }

    /// Полный бэкап: сессии + настройки + текущая живая сессия.
    func backupData() throws -> Data {
        let backup = Backup(
            exportedAt: .now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            preferences: preferences,
            liveSession: liveSession,
            sessions: sessions
        )
        do { return try StraddleCoding.makeEncoder().encode(backup) }
        catch { throw StoreError.encode(error.localizedDescription) }
    }

    static func backupFileName(date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return "Straddle-backup-\(formatter.string(from: date)).json"
    }

    func markBackedUp() {
        updatePreferences { $0.lastBackupAt = .now }
    }

    /// Понимает: новый формат бэкапа, старый sessions.json (просто массив),
    /// объект с ключом "sessions", UTF-8 BOM. Битые записи пропускаются, а не валят весь импорт.
    static func parseBackup(_ raw: Data) throws -> ParsedBackup {
        var data = raw
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = data.dropFirst(3) }
        guard !data.isEmpty else { throw StoreError.decode("The file is empty") }
        let decoder = StraddleCoding.makeDecoder()
        if let lossy = try? decoder.decode(LossyArray<PokerSession>.self, from: data) {
            return ParsedBackup(sessions: lossy.values, preferences: nil, liveSession: nil, skipped: lossy.skipped)
        }
        do {
            let wrapper = try decoder.decode(LossyBackup.self, from: data)
            return ParsedBackup(sessions: wrapper.sessions.values,
                                preferences: wrapper.preferences,
                                liveSession: wrapper.liveSession,
                                skipped: wrapper.sessions.skipped)
        } catch {
            throw StoreError.decode(Self.describe(error))
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        switch decoding {
        case .dataCorrupted(let context): return "Not valid JSON (\(context.debugDescription))"
        case .keyNotFound(let key, _): return "Missing \"\(key.stringValue)\""
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "Unexpected value at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        @unknown default: return error.localizedDescription
        }
    }

    /// Читает выбранный в «Файлах» документ (в т.ч. из iCloud Drive) и готовит превью импорта.
    func prepareImport(from url: URL) throws -> ImportPreview {
        let data = try Self.readExternalFile(url)
        let parsed = try Self.parseBackup(data)
        guard !parsed.sessions.isEmpty || parsed.liveSession != nil else {
            throw StoreError.decode("No sessions found in this file")
        }
        let existing = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let unique = Self.deduplicated(parsed.sessions)
        let newCount = unique.filter { existing[$0.id] == nil }.count
        let updatedCount = unique.filter { incoming in
            guard let current = existing[incoming.id] else { return false }
            return incoming != current && incoming.updatedAt >= current.updatedAt
        }.count
        return ImportPreview(fileName: url.lastPathComponent,
                             sessions: unique,
                             preferences: parsed.preferences,
                             liveSession: parsed.liveSession,
                             skipped: parsed.skipped,
                             newCount: newCount,
                             updatedCount: updatedCount)
    }

    func applyImport(_ preview: ImportPreview, replace: Bool) throws {
        if replace { try replaceAll(preview.sessions) } else { try merge(preview.sessions) }
        if let prefs = preview.preferences {
            updatePreferences { current in
                current.rates.merge(prefs.rates) { _, new in new }
                if replace || current.defaultCurrency == Currency.base { current.defaultCurrency = prefs.defaultCurrency }
            }
        }
        if liveSession == nil, let live = preview.liveSession, !sessions.contains(where: { $0.id == live.id }) {
            try persistLive(live)
        }
    }

    static func readExternalFile(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(StoreError.read("Unknown error"))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readURL in
            result = Result { try Data(contentsOf: readURL) }
        }
        if let coordinationError { throw StoreError.read(coordinationError.localizedDescription) }
        do { return try result.get() }
        catch { throw StoreError.read(error.localizedDescription) }
    }

    /// CSV для таблиц (Numbers / Google Sheets).
    func csvData() -> Data {
        let header = "date,type,game,stakes,venue,currency,rate_per_usd,buy_in,cash_out,profit,rebuys,buy_in_usd,cash_out_usd,profit_usd,minutes,notes"
        let iso = ISO8601DateFormatter()
        func esc(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        func num(_ value: Decimal) -> String { NSDecimalNumber(decimal: value.rounded(2)).stringValue }
        let rows: [String] = sessions.map { s in
            var fields: [String] = []
            fields.append(iso.string(from: s.date))
            fields.append(esc(s.type.shortName))
            fields.append(esc(s.game))
            fields.append(esc(s.stakes))
            fields.append(esc(s.venue))
            fields.append(s.currency)
            fields.append(NSDecimalNumber(decimal: s.exchangeRate).stringValue)
            fields.append(num(s.buyIn))
            fields.append(num(s.cashOut))
            fields.append(num(s.nativeProfit))
            fields.append(String(s.rebuyCount))
            fields.append(num(s.buyInUSD))
            fields.append(num(s.cashOutUSD))
            fields.append(num(s.profit))
            fields.append(String(s.durationMinutes))
            fields.append(esc(s.notes))
            return fields.joined(separator: ",")
        }
        return Data(([header] + rows).joined(separator: "\n").utf8)
    }

    /// Сессии, у которых валюта USD (в т.ч. все записанные до появления валют).
    var usdSessionCount: Int { sessions.filter { !$0.isForeignCurrency }.count }

    /// Помечает все USD-сессии как сыгранные в `code` по курсу `rate`. Суммы не меняются —
    /// меняется лишь то, в какой валюте они записаны (для старых записей в местной валюте).
    func assignCurrencyToUSDSessions(_ code: String, rate: Decimal) throws {
        guard code != Currency.base, rate > 0 else { return }
        let updated = sessions.map { session -> PokerSession in
            guard !session.isForeignCurrency else { return session }
            var value = session
            value.currency = code
            value.exchangeRate = rate
            value.updatedAt = .now
            return value
        }
        try commit(updated)
        rememberCurrency(code, rate: rate)
    }

    func deleteAllSessions() throws {
        try commit([])
    }
}

// MARK: - Lossy decoding

private struct LossyArray<Element: Decodable>: Decodable {
    var values: [Element] = []
    var skipped = 0

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            let item = try container.decode(LossyItem<Element>.self)
            if let value = item.value { values.append(value) } else { skipped += 1 }
        }
    }
}

private struct LossyItem<Element: Decodable>: Decodable {
    let value: Element?
    init(from decoder: Decoder) throws { value = try? Element(from: decoder) }
}

private struct LossyBackup: Decodable {
    let sessions: LossyArray<PokerSession>
    let preferences: Preferences?
    let liveSession: LiveSession?

    enum CodingKeys: String, CodingKey { case sessions, preferences, liveSession }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessions = try c.decode(LossyArray<PokerSession>.self, forKey: .sessions)
        preferences = try? c.decodeIfPresent(Preferences.self, forKey: .preferences)
        liveSession = try? c.decodeIfPresent(LiveSession.self, forKey: .liveSession)
    }
}
