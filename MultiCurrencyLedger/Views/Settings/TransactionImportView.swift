import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct TransactionImportView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query(sort: \LedgerBook.createdAt) private var books: [LedgerBook]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query private var transactions: [LedgerTransaction]
    @Query private var fingerprints: [TransactionImportFingerprint]
    @Query(sort: \TransactionImportBatch.createdAt, order: .reverse) private var batches: [TransactionImportBatch]

    @State private var showingFileImporter = false
    @State private var sourceName = ""
    @State private var table: SpreadsheetTable?
    @State private var preset = TransactionImportPreset.automatic
    @State private var mapping = TransactionImportMapping()
    @State private var bookID = ""
    @State private var walletID = ""
    @State private var preview: TransactionImportPreview?
    @State private var errorReportURL: URL?
    @State private var message: ImportMessage?
    @State private var undoBatch: TransactionImportBatch?

    private var selectedBookUUID: UUID? { UUID(uuidString: bookID) }
    private var scopedWallets: [CurrencyWallet] {
        guard let selectedBookUUID else { return [] }
        return accounts
            .filter { $0.book?.id == selectedBookUUID && !$0.isArchived }
            .flatMap(\.enabledWallets)
            .sorted {
                ($0.account?.name ?? "", $0.currencyCode) < ($1.account?.name ?? "", $1.currencyCode)
            }
    }
    private var selectedWallet: CurrencyWallet? {
        let id = UUID(uuidString: walletID)
        return scopedWallets.first { $0.id == id }
    }

    var body: some View {
        List {
            sourceSection
            if let table { configurationSection(table) }
            if let preview { previewSection(preview) }
            historySection
        }
        .navigationTitle("账单导入")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: initializeSelection)
        .onChange(of: preset) { _, value in
            guard let table else { return }
            mapping = .suggested(headers: table.headers, preset: value)
            preview = nil
        }
        .onChange(of: bookID) { _, _ in
            walletID = scopedWallets.first?.id.uuidString ?? ""
            preview = nil
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: allowedTypes,
            allowsMultipleSelection: false,
            onCompletion: handleFile
        )
        .confirmationDialog(
            "撤销这次导入？",
            isPresented: Binding(
                get: { undoBatch != nil },
                set: { if !$0 { undoBatch = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("撤销并恢复余额", role: .destructive, action: undoSelectedBatch)
            Button("取消", role: .cancel) { undoBatch = nil }
        } message: {
            Text("仅删除该批次生成的流水；之后手动编辑的同一笔流水也会一并删除。")
        }
        .alert(item: $message) { message in
            Alert(title: Text(message.title), message: Text(message.detail), dismissButton: .default(Text("好")))
        }
    }

    private var sourceSection: some View {
        Section("文件") {
            Button {
                showingFileImporter = true
            } label: {
                Label(sourceName.isEmpty ? "选择 CSV / XLSX" : sourceName, systemImage: "doc.badge.plus")
            }
            Text("文件只在本机解析。导入前可检查字段映射与每一行结果，重复流水不会再次写入。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func configurationSection(_ table: SpreadsheetTable) -> some View {
        Section {
            Picker("格式预设", selection: $preset) {
                ForEach(TransactionImportPreset.allCases) { Text($0.title).tag($0) }
            }
            Picker("导入账本", selection: $bookID) {
                ForEach(books) { Text($0.name).tag($0.id.uuidString) }
            }
            Picker("默认钱包", selection: $walletID) {
                Text("不指定").tag("")
                ForEach(scopedWallets) { wallet in
                    Text("\(wallet.account?.name ?? "账户") · \(wallet.currencyCode)")
                        .tag(wallet.id.uuidString)
                }
            }
            DisclosureGroup("字段映射") {
                ForEach(TransactionImportField.allCases) { field in
                    Picker(field.title + (field.isRequired ? " *" : ""), selection: mappingBinding(field)) {
                        Text("不映射").tag(-1)
                        ForEach(table.headers.indices, id: \.self) { index in
                            Text(table.headers[index]).tag(index)
                        }
                    }
                }
            }
            Button("生成导入预览", action: buildPreview)
                .disabled(bookID.isEmpty || mapping[.amount] == nil)
        } header: {
            Text("确认映射")
        } footer: {
            Text("共读取 \(table.rows.count) 行。每行若没有可匹配账户，将使用默认钱包；分类不匹配的行会明确报错。")
        }
    }

    private func previewSection(_ preview: TransactionImportPreview) -> some View {
        Section {
            LabeledContent("可导入", value: "\(preview.readyRows.count)")
            LabeledContent("重复跳过", value: "\(preview.duplicateCount)")
            LabeledContent("错误行", value: "\(preview.errorCount)")
            if let errorReportURL, preview.errorCount > 0 {
                ShareLink(item: errorReportURL) {
                    Label("分享错误行报告", systemImage: "square.and.arrow.up")
                }
            }
            ForEach(preview.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.summary).lineLimit(1)
                        Spacer()
                        if let amount = row.amount, let currency = row.currencyCode {
                            Text(MoneyFormatter.plain(amount, currencyCode: currency) + " " + currency)
                                .monospacedDigit()
                        }
                    }
                    Text(row.status.title)
                        .font(.caption)
                        .foregroundStyle(statusColor(row.status))
                }
            }
            Button("导入 \(preview.readyRows.count) 笔流水", action: commitPreview)
                .buttonStyle(.borderedProminent)
                .disabled(preview.readyRows.isEmpty)
        } header: {
            Text("逐行预览")
        } footer: {
            Text("整批写入是原子操作：任意一笔校验或保存失败时，不会留下部分流水或错误余额。")
        }
    }

    private var historySection: some View {
        Section("最近导入") {
            if batches.isEmpty {
                Text("还没有导入记录").foregroundStyle(.secondary)
            }
            ForEach(batches.prefix(20)) { batch in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(batch.sourceName).lineLimit(1)
                        Text("\(batch.preset.title) · 成功 \(batch.importedCount) · 跳过 \(batch.skippedCount) · 错误 \(batch.errorCount)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(batch.createdAt, format: .dateTime.year().month().day().hour().minute())
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if batch.undoneAt == nil {
                        Button("撤销") { undoBatch = batch }.buttonStyle(.borderless)
                    } else {
                        Text("已撤销").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var allowedTypes: [UTType] {
        var values: [UTType] = [.commaSeparatedText, .tabSeparatedText, .plainText]
        if let xlsx = UTType(filenameExtension: "xlsx") { values.append(xlsx) }
        return values
    }

    private func mappingBinding(_ field: TransactionImportField) -> Binding<Int> {
        Binding(
            get: { mapping[field] ?? -1 },
            set: { mapping[field] = $0 < 0 ? nil : $0; preview = nil }
        )
    }

    private func initializeSelection() {
        if bookID.isEmpty {
            bookID = UUID(uuidString: selectedBookID).flatMap { selected in
                books.contains(where: { $0.id == selected }) ? selected.uuidString : nil
            } ?? books.first?.id.uuidString ?? ""
        }
        if walletID.isEmpty { walletID = scopedWallets.first?.id.uuidString ?? "" }
    }

    private func handleFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let decoded = try SpreadsheetImportDecoder.decode(data: data, fileExtension: url.pathExtension)
            sourceName = url.lastPathComponent
            table = decoded
            preset = .automatic
            mapping = .suggested(headers: decoded.headers, preset: .automatic)
            preview = nil
            errorReportURL = nil
        } catch {
            message = ImportMessage(title: "无法读取文件", detail: error.localizedDescription)
        }
    }

    private func buildPreview() {
        guard let table, let selectedBookUUID else { return }
        do {
            let result = try TransactionImportService(context: context).preview(
                table: table,
                sourceName: sourceName,
                preset: preset,
                mapping: mapping,
                bookID: selectedBookUUID,
                defaultWallet: selectedWallet,
                wallets: scopedWallets,
                categories: categories,
                existingFingerprints: fingerprints
            )
            preview = result
            errorReportURL = try TransactionImportErrorReport.make(for: result)
        } catch {
            message = ImportMessage(title: "无法生成预览", detail: error.localizedDescription)
        }
    }

    private func commitPreview() {
        guard let preview else { return }
        do {
            let batch = try TransactionImportService(context: context).commit(preview)
            self.preview = nil
            errorReportURL = nil
            message = ImportMessage(title: "导入完成", detail: "已写入 \(batch.importedCount) 笔，重复跳过 \(batch.skippedCount) 笔。")
        } catch {
            context.rollback()
            message = ImportMessage(title: "导入失败", detail: error.localizedDescription)
        }
    }

    private func undoSelectedBatch() {
        guard let batch = undoBatch else { return }
        undoBatch = nil
        do {
            try TransactionImportService(context: context).undo(
                batch,
                transactions: transactions,
                fingerprints: fingerprints
            )
            message = ImportMessage(title: "已撤销", detail: "该批次流水与余额变化已经恢复。")
        } catch {
            context.rollback()
            message = ImportMessage(title: "撤销失败", detail: error.localizedDescription)
        }
    }

    private func statusColor(_ status: TransactionImportRowStatus) -> Color {
        switch status {
        case .ready: .green
        case .duplicate: .orange
        case .invalid: .red
        }
    }
}

private struct ImportMessage: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

private enum TransactionImportErrorReport {
    static func make(for preview: TransactionImportPreview) throws -> URL? {
        let errors = preview.rows.filter { if case .invalid = $0.status { true } else { false } }
        guard !errors.isEmpty else { return nil }
        let lines = (["行号,错误,原始数据"] + errors.map { row in
            let values = row.rawValues.joined(separator: " | ")
            return [String(row.id), row.status.title, values].map(csv).joined(separator: ",")
        }).joined(separator: "\r\n")
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(lines.utf8))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("导入错误报告-\(UUID().uuidString.prefix(8)).csv")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func csv(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
