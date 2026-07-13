import SwiftData
import SwiftUI
import PhotosUI
import UIKit

struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \TransactionAttachment.createdAt) private var allAttachments: [TransactionAttachment]
    @Query(sort: \TransactionRelation.createdAt, order: .reverse)
    private var allRelations: [TransactionRelation]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    let transaction: LedgerTransaction
    @State private var showingEdit = false
    @State private var showingCopy = false
    @State private var showingDelete = false
    @State private var errorMessage: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingTemplateName = false
    @State private var templateName = ""
    @State private var relationKind: TransactionRelationKind?

    private var attachments: [TransactionAttachment] {
        allAttachments.filter { $0.transactionID == transaction.id }
    }

    private var relations: [TransactionRelation] {
        allRelations.filter { $0.originalTransactionID == transaction.id }
    }

    private var relationWallets: [CurrencyWallet] {
        let bookID = transaction.sourceAccount?.book?.id
        let currencyCode = transaction.sourceCurrencyCode ?? transaction.currencyCode
        return accounts
            .filter { !$0.isArchived && $0.book?.id == bookID }
            .flatMap(\.enabledWallets)
            .filter { $0.currencyCode == currencyCode }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: transaction.type.symbolName)
                            .font(.largeTitle).foregroundStyle(transaction.type.color)
                        Text(transaction.summaryAmount)
                            .font(.title2.bold()).monospacedDigit()
                        Text(transaction.type.title).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical)
            }

            Section("交易信息") {
                LabeledContent("日期", value: transaction.date.formatted(date: .long, time: .shortened))
                if let category = transaction.category { LabeledContent("分类", value: category.name) }
                if !transaction.tags.isEmpty {
                    LabeledContent("标签", value: transaction.tags.map(\.name).sorted().joined(separator: "、"))
                }
                if let merchant = transaction.merchantOrCounterparty { LabeledContent("商户", value: merchant) }
                if transaction.paymentParts.count >= 2 {
                    ForEach(transaction.paymentParts.sorted(by: { $0.sortOrder < $1.sortOrder })) { part in
                        LabeledContent(
                            part.wallet?.account?.name ?? "付款钱包",
                            value: MoneyFormatter.string(part.amount, currencyCode: part.wallet?.currencyCode ?? transaction.sourceCurrencyCode ?? "CNY")
                        )
                    }
                }
                if let account = transaction.sourceAccount { LabeledContent("来源账户", value: account.name) }
                if let code = transaction.sourceCurrencyCode { LabeledContent("来源币种", value: code) }
                if let account = transaction.destinationAccount { LabeledContent("目标账户", value: account.name) }
                if let code = transaction.destinationCurrencyCode { LabeledContent("目标币种", value: code) }
                if let rate = transaction.exchangeRate { LabeledContent("实际汇率", value: "\(rate)") }
                if let fee = transaction.feeAmount, fee > 0 {
                    LabeledContent("手续费", value: "\(MoneyFormatter.plain(fee, currencyCode: transaction.feeCurrencyCode ?? "CNY")) \(transaction.feeCurrencyCode ?? "")")
                }
                if let original = transaction.originalAmount {
                    LabeledContent("原价", value: MoneyFormatter.plain(original, currencyCode: transaction.currencyCode ?? transaction.sourceCurrencyCode ?? "CNY"))
                }
                if let discount = transaction.discountAmount, discount > 0 {
                    LabeledContent("优惠", value: MoneyFormatter.plain(discount, currencyCode: transaction.currencyCode ?? transaction.sourceCurrencyCode ?? "CNY"))
                }
                if transaction.recognitionImportID != nil { LabeledContent("来源", value: "截图识别") }
                if let reason = transaction.adjustmentReason { LabeledContent("调整原因", value: reason) }
                if let note = transaction.note, !note.isEmpty { LabeledContent("备注", value: note) }
            }

            Section("图片附件") {
                ForEach(attachments) { attachment in
                    AttachmentRow(attachment: attachment)
                        .swipeActions {
                            Button("删除", role: .destructive) { removeAttachment(attachment) }
                        }
                }
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("添加图片", systemImage: "photo.badge.plus")
                }
            }

            if !relations.isEmpty {
                Section("退款与报销") {
                    ForEach(relations) { relation in
                        LabeledContent(
                            relation.kind.title,
                            value: MoneyFormatter.string(
                                relation.amount,
                                currencyCode: transaction.sourceCurrencyCode ?? transaction.currencyCode ?? "CNY"
                            )
                        )
                    }
                }
            }

            Section {
                Button("编辑") { showingEdit = true }
                Button("复制记账") { showingCopy = true }
                Button("保存为模板") {
                    templateName = transaction.merchantOrCounterparty ?? transaction.category?.name ?? transaction.type.title
                    showingTemplateName = true
                }
                if transaction.type == .expense {
                    Button("记录退款") { relationKind = .refund }
                    Button("记录报销") { relationKind = .reimbursement }
                }
                Button("删除交易", role: .destructive) { showingDelete = true }
            }
        }
        .navigationTitle("交易详情")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEdit) {
            TransactionEditView(transaction: transaction) { dismiss() }
        }
        .sheet(isPresented: $showingCopy) {
            EntryView(
                seed: TransactionDraft(transaction: transaction),
                dismissAfterSave: true
            )
        }
        .sheet(item: $relationKind) { kind in
            TransactionRelationEntryView(
                original: transaction,
                kind: kind,
                wallets: relationWallets
            )
        }
        .confirmationDialog("确定删除这笔交易？", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("删除并回滚余额", role: .destructive, action: deleteTransaction)
            Button("取消", role: .cancel) {}
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
        }
        .alert("保存为模板", isPresented: $showingTemplateName) {
            TextField("模板名称", text: $templateName)
            Button("取消", role: .cancel) {}
            Button("保存", action: saveAsTemplate)
        } message: {
            Text("模板会保存当前交易的账户、分类、标签和金额，使用时仍需确认后入账。")
        }
    }

    private func deleteTransaction() {
        do {
            try LedgerService(context: context).deleteTransaction(transaction)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func importPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw AttachmentError.emptyData
            }
            try AttachmentService(context: context).addImage(data: data, to: transaction)
            selectedPhoto = nil
        } catch {
            selectedPhoto = nil
            errorMessage = error.localizedDescription
        }
    }

    private func removeAttachment(_ attachment: TransactionAttachment) {
        do {
            try AttachmentService(context: context).remove(attachment)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveAsTemplate() {
        do {
            try TransactionTemplateService(context: context).create(
                name: templateName,
                from: TransactionDraft(transaction: transaction)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TransactionRelationEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let original: LedgerTransaction
    let kind: TransactionRelationKind
    let wallets: [CurrencyWallet]
    @State private var amountText = ""
    @State private var walletID: UUID?
    @State private var date = Date.now
    @State private var note = ""
    @State private var remaining: Decimal = 0
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("\(kind.title)金额") {
                    TextField("金额", text: $amountText).keyboardType(.decimalPad)
                    Text("最多可记录 \(MoneyFormatter.string(remaining, currencyCode: original.sourceCurrencyCode ?? "CNY"))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("入账") {
                    Picker("钱包", selection: $walletID) {
                        ForEach(wallets) { wallet in
                            Text("\(wallet.account?.name ?? "账户") / \(wallet.currencyCode)")
                                .tag(wallet.id as UUID?)
                        }
                    }
                    DatePicker("日期", selection: $date)
                    TextField("备注（可选）", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("记录\(kind.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .onAppear {
                walletID = wallets.first?.id
                remaining = (try? TransactionRelationService(context: context).summary(for: original).remaining) ?? 0
                amountText = NSDecimalNumber(decimal: remaining).stringValue
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
        }
    }

    private func save() {
        do {
            guard let amount = DecimalParser.parse(amountText),
                  let wallet = wallets.first(where: { $0.id == walletID }) else {
                throw TransactionRelationError.invalidAmount
            }
            try TransactionRelationService(context: context).record(
                kind: kind,
                original: original,
                amount: amount,
                wallet: wallet,
                date: date,
                note: note
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AttachmentRow: View {
    @Environment(\.modelContext) private var context
    let attachment: TransactionAttachment

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let url = try? AttachmentService(context: context).fileURL(for: attachment),
                   let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 54, height: 54)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(attachment.originalFilename).lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
