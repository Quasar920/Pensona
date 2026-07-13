import SwiftData
import SwiftUI

struct SmartDraftEntryView: View {
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query(sort: \LedgerBook.createdAt) private var books: [LedgerBook]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query(sort: \TransactionTag.name) private var tags: [TransactionTag]
    @StateObject private var transcriber = SpeechDraftTranscriber()
    @State private var text = ""
    @State private var result: SmartDraftParseResult?
    @State private var pendingRoute: SmartDraftRoute?
    @State private var errorMessage: String?

    private var bookID: UUID? { UUID(uuidString: selectedBookID) ?? books.first?.id }
    private var wallets: [CurrencyWallet] {
        guard let bookID else { return [] }
        return accounts.filter { $0.book?.id == bookID && !$0.isArchived }.flatMap(\.enabledWallets)
    }
    private var scopedCategories: [LedgerCategory] {
        guard let bookID else { return [] }
        return categories.filter { !$0.isArchived && ($0.bookID == nil || $0.bookID == bookID) }
    }
    private var scopedTags: [TransactionTag] {
        guard let bookID else { return [] }
        return tags.filter { !$0.isArchived && $0.bookID == bookID }
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 120)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("例如：昨天用支付宝花 28.5 元吃午饭 #工作")
                                .foregroundStyle(.tertiary).padding(.top, 8).allowsHitTesting(false)
                        }
                    }
                HStack {
                    Button {
                        Task {
                            if transcriber.isRecording { transcriber.stop() }
                            else { await transcriber.start() }
                        }
                    } label: {
                        Label(transcriber.isRecording ? "停止听写" : "语音听写",
                              systemImage: transcriber.isRecording ? "stop.circle.fill" : "waveform.circle.fill")
                    }
                    Spacer()
                    Button("解析草稿", action: parse)
                        .buttonStyle(.borderedProminent)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("文本或语音")
            } footer: {
                Text("支持支出、收入、转账、换汇、金额、账户、分类、日期和 #标签；解析不会自动入账。")
            }

            if let result {
                Section("解析结果") {
                    LabeledContent("类型", value: result.draft.type.title)
                    LabeledContent("金额", value: MoneyFormatter.plain(
                        result.draft.amount,
                        currencyCode: result.draft.sourceWallet?.currencyCode ?? "CNY"
                    ))
                    LabeledContent("账户", value: result.draft.sourceWallet?.account?.name ?? "-")
                    if let category = result.draft.category { LabeledContent("分类", value: category.name) }
                    ForEach(result.warnings, id: \.self) {
                        Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    Button("打开统一确认页") { pendingRoute = SmartDraftRoute(result: result) }
                }
            }
        }
        .navigationTitle("智能草稿")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: transcriber.transcript) { _, value in
            if !value.isEmpty { text = value }
        }
        .onChange(of: transcriber.errorMessage) { _, value in errorMessage = value }
        .onDisappear { transcriber.stop() }
        .sheet(item: $pendingRoute) { route in
            EntryView(
                seed: route.result.draft,
                dismissAfterSave: true,
                resetSeedDate: false,
                presentationTitle: "确认智能草稿"
            )
        }
        .alert("无法生成草稿", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
    }

    private func parse() {
        do {
            result = try SmartDraftService().parse(
                text,
                wallets: wallets,
                categories: scopedCategories,
                tags: scopedTags
            )
        } catch {
            result = nil
            errorMessage = error.localizedDescription
        }
    }
}

private struct SmartDraftRoute: Identifiable {
    let id = UUID()
    let result: SmartDraftParseResult
}
