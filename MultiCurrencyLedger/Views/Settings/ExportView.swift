import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ExportView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.CNY.rawValue
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query private var books: [LedgerBook]
    @Query private var transactions: [LedgerTransaction]
    @State private var jsonURL: URL?
    @State private var csvURL: URL?
    @State private var errorMessage: String?
    @State private var showingRestoreImporter = false
    @State private var pendingRestoreData: Data?
    @State private var pendingPreview: BackupPreview?
    @State private var showingRestoreConfirmation = false
    @State private var recoveryURL: URL?
    @State private var successMessage: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("JSON 完整备份", systemImage: "curlybraces")
                        .font(.headline)
                    Text("包含全部账本数据、自动化规则、预算目标、导入记录和图片附件内容。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let jsonURL {
                        ShareLink(item: jsonURL) {
                            Label("分享 JSON 备份", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button("生成 JSON 备份", action: prepareJSON)
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("校验并恢复备份", systemImage: "arrow.counterclockwise.icloud")
                        .font(.headline)
                    Text("先预览数量和兼容性；确认恢复前会自动保存当前完整快照，失败时恢复原数据库和附件目录。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("选择 JSON 备份") { showingRestoreImporter = true }
                    if let preview = pendingPreview {
                        Group {
                            LabeledContent("备份版本", value: "\(preview.version)")
                            LabeledContent("账本 / 账户", value: "\(preview.bookCount) / \(preview.accountCount)")
                            LabeledContent("流水 / 附件", value: "\(preview.transactionCount) / \(preview.attachmentCount)")
                            LabeledContent("本位币", value: preview.baseCurrencyCode)
                        }
                        .font(.footnote)
                        ForEach(preview.warnings, id: \.self) {
                            Label($0, systemImage: "exclamationmark.triangle")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                        Button("恢复此备份", role: .destructive) { showingRestoreConfirmation = true }
                    }
                    if let recoveryURL {
                        ShareLink(item: recoveryURL) {
                            Label("分享恢复前快照", systemImage: "lifepreserver")
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("CSV 交易明细", systemImage: "tablecells")
                        .font(.headline)
                    Text("按日期导出全部流水，使用 UTF-8 编码并兼容常见表格软件。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let csvURL {
                        ShareLink(item: csvURL) {
                            Label("分享 CSV 流水", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button("生成 CSV 流水", action: prepareCSV)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("备份、恢复与导出")
        .fileImporter(
            isPresented: $showingRestoreImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: loadRestoreFile
        )
        .confirmationDialog(
            "使用备份替换当前全部数据？",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("确认恢复", role: .destructive, action: restoreBackup)
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前数据会先生成自动快照。恢复完成后，本位币也会切换为备份中的设置。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
        .alert("操作完成", isPresented: Binding(
            get: { successMessage != nil },
            set: { if !$0 { successMessage = nil } }
        )) { Button("好") {} } message: { Text(successMessage ?? "") }
    }

    private func prepareJSON() {
        do {
            jsonURL = try BackupService.makeBackupFile(context: context, baseCurrencyCode: baseCurrencyCode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareCSV() {
        do {
            csvURL = try ExportService.makeCSV(transactions: transactions)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadRestoreFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            pendingPreview = try BackupService.preview(data: data)
            pendingRestoreData = data
        } catch {
            pendingPreview = nil
            pendingRestoreData = nil
            errorMessage = error.localizedDescription
        }
    }

    private func restoreBackup() {
        guard let pendingRestoreData else { return }
        do {
            let result = try BackupService.restore(
                data: pendingRestoreData,
                context: context,
                currentBaseCurrencyCode: baseCurrencyCode
            )
            baseCurrencyCode = result.settings.baseCurrencyCode
            selectedBookID = books.first?.id.uuidString ?? ""
            recoveryURL = result.recoveryURL
            self.pendingRestoreData = nil
            pendingPreview = nil
            successMessage = "备份恢复完成。恢复前快照已保留，可随时分享或再次恢复。"
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
