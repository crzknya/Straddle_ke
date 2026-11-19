import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var exportDocument: BackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var preview: ImportPreview?
    @State private var shareItem: ShareItem?
    @State private var message: String?
    @State private var confirmReplace = false
    @State private var confirmDeleteAll = false
    @State private var convertCurrency = "KES"
    @State private var convertRate: Decimal?
    @State private var confirmConvert = false

    var body: some View {
        // Экспорт и импорт висят на разных view: на одном view они конфликтуют в iOS.
        VStack(spacing: 0) {
            Form {
                backupSection
                importSection
                currencySection
                convertSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .fileExporter(isPresented: $exporting,
                          document: exportDocument,
                          contentType: .json,
                          defaultFilename: SessionStore.backupFileName()) { result in
                switch result {
                case .success:
                    store.markBackedUp()
                    message = "Backup saved: \(store.sessions.count) sessions."
                case .failure(let error):
                    message = "Backup failed: \(error.localizedDescription)"
                }
                exportDocument = nil
            }
        }
        .background(StraddleTheme.background)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json, .plainText, .data],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do { preview = try store.prepareImport(from: url) }
                catch { message = error.localizedDescription }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .confirmationDialog("Replace all \(store.sessions.count) current sessions with the file’s \(preview?.sessions.count ?? 0)?",
                            isPresented: $confirmReplace, titleVisibility: .visible) {
            Button("Replace all", role: .destructive) {
                if let preview { apply(preview, replace: true) }
            }
        }
        .confirmationDialog("Mark \(store.usdSessionCount) USD sessions as \(convertCurrency) at 1 USD = \(convertRate.map(AmountParser.editableText) ?? "?")?",
                            isPresented: $confirmConvert, titleVisibility: .visible) {
            Button("Convert") {
                do {
                    try store.assignCurrencyToUSDSessions(convertCurrency, rate: convertRate ?? 0)
                    message = "Done. Statistics are now converted to USD."
                } catch { message = error.localizedDescription }
            }
        }
        .confirmationDialog("Delete all \(store.sessions.count) sessions? Make a backup first.", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { try? store.deleteAllSessions() }
        }
        .navigationTitle("Settings")
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url]).presentationDetents([.medium, .large])
        }
        .alert("Straddle", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    // MARK: Backup

    private var backupSection: some View {
        Section {
            HStack {
                Label("Last backup", systemImage: "clock.arrow.circlepath")
                Spacer()
                Text(lastBackupText).foregroundStyle(backupIsStale ? StraddleTheme.negative : StraddleTheme.secondaryText)
            }
            Button {
                do {
                    exportDocument = BackupDocument(data: try store.backupData())
                    exporting = true
                } catch { message = error.localizedDescription }
            } label: {
                Label("Save backup to Files…", systemImage: "folder.badge.plus")
            }
            Button {
                share(data: { try store.backupData() }, name: SessionStore.backupFileName(), markBackup: true)
            } label: {
                Label("Share backup (Telegram, Mail, AirDrop)…", systemImage: "square.and.arrow.up")
            }
            Button {
                share(data: { store.csvData() }, name: "Straddle-sessions.csv", markBackup: false)
            } label: {
                Label("Export CSV for spreadsheets", systemImage: "tablecells")
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("Deleting the app deletes its data. Before reinstalling, save a backup to Files (e.g. iCloud Drive or “On My iPhone”, outside the Straddle folder), then use Import after installing. Installing a new build over the old one keeps your data.")
        }
    }

    private func share(data: () throws -> Data, name: String, markBackup: Bool) {
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Share", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(name)
            try data().write(to: url, options: .atomic)
            if markBackup { store.markBackedUp() }
            shareItem = ShareItem(url: url)
        } catch {
            message = error.localizedDescription
        }
    }

    private var lastBackupText: String {
        guard let date = store.preferences.lastBackupAt else { return "Never" }
        return date.formatted(.relative(presentation: .named))
    }

    private var backupIsStale: Bool {
        guard !store.sessions.isEmpty else { return false }
        guard let date = store.preferences.lastBackupAt else { return true }
        return Date.now.timeIntervalSince(date) > 14 * 24 * 3600
    }

    // MARK: Import

    @ViewBuilder private var importSection: some View {
        Section {
            Button {
                preview = nil
                importing = true
            } label: {
                Label("Import backup…", systemImage: "square.and.arrow.down")
            }

            if let preview {
                VStack(alignment: .leading, spacing: 6) {
                    Text(preview.fileName).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("\(preview.sessions.count) sessions in file • \(preview.newCount) new • \(preview.updatedCount) updated")
                        .font(.caption).foregroundStyle(StraddleTheme.secondaryText)
                    if preview.skipped > 0 {
                        Text("\(preview.skipped) damaged entries will be skipped.").font(.caption).foregroundStyle(.orange)
                    }
                    if preview.liveSession != nil && store.liveSession == nil {
                        Text("Includes a live session in progress.").font(.caption).foregroundStyle(StraddleTheme.cyan)
                    }
                }
                .padding(.vertical, 4)
                Button {
                    apply(preview, replace: false)
                } label: {
                    Label("Merge with current data", systemImage: "arrow.triangle.merge")
                }
                Button(role: .destructive) {
                    confirmReplace = true
                } label: {
                    Label("Replace all current data", systemImage: "arrow.counterclockwise")
                }
                Button("Cancel", role: .cancel) { self.preview = nil }
            }
        } header: {
            Text("Restore")
        } footer: {
            Text("Accepts Straddle backups and old sessions.json files. Merge keeps everything and never creates duplicates.")
        }
    }

    private func apply(_ value: ImportPreview, replace: Bool) {
        do {
            try store.applyImport(value, replace: replace)
            preview = nil
            message = "Import complete. You now have \(store.sessions.count) sessions."
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: Currency

    private var currencySection: some View {
        Section {
            Picker("Default game currency", selection: Binding(
                get: { store.preferences.defaultCurrency },
                set: { code in store.updatePreferences { $0.defaultCurrency = code } }
            )) {
                ForEach(Currency.all, id: \.self) { Text(Currency.label($0)).tag($0) }
            }
            .pickerStyle(.navigationLink)

            ForEach(store.preferences.rates.keys.sorted(), id: \.self) { code in
                HStack {
                    Text("1 USD")
                    Spacer()
                    Text((store.preferences.rates[code] ?? 0).currencyText(code)).monospacedDigit()
                }
            }
            .onDelete { offsets in
                let codes = store.preferences.rates.keys.sorted()
                store.updatePreferences { prefs in
                    for index in offsets { prefs.rates.removeValue(forKey: codes[index]) }
                }
            }
        } header: {
            Text("Currency")
        } footer: {
            Text("All statistics are shown in US dollars. Each session keeps its own currency and the rate you entered, so later rate changes don’t rewrite history. Saved rates are pre-filled for new sessions.")
        }
    }

    // MARK: Old sessions

    @ViewBuilder private var convertSection: some View {
        if store.usdSessionCount > 0 {
            Section {
                CurrencyRateFields(currency: $convertCurrency, rate: $convertRate)
                Button("Mark \(store.usdSessionCount) USD sessions as \(convertCurrency)") { confirmConvert = true }
                    .disabled(convertCurrency == Currency.base || (convertRate ?? 0) <= 0)
            } header: {
                Text("Sessions recorded in local currency")
            } footer: {
                Text("Older versions showed the phone’s local currency, so earlier sessions may have been entered in shillings but are now treated as dollars. This keeps the amounts and records them as the chosen currency at this rate. A single session can also be fixed via Edit.")
            }
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            HStack { Text("Sessions"); Spacer(); Text("\(store.sessions.count)").foregroundStyle(StraddleTheme.secondaryText) }
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—").foregroundStyle(StraddleTheme.secondaryText)
            }
            Button("Delete all sessions", role: .destructive) { confirmDeleteAll = true }
                .disabled(store.sessions.isEmpty)
        } header: {
            Text("Data")
        } footer: {
            Text("Data is stored on this iPhone in Files → On My iPhone → Straddle → sessions.json.")
        }
    }
}
