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
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query(sort: \LedgerTransaction.date, order: .reverse) private var allTransactions: [LedgerTransaction]
    @Query private var allAASplits: [AASplit]
    @Query private var allAASettlements: [AASettlement]
    let transaction: LedgerTransaction
    @State private var showingEdit = false
    @State private var showingCopy = false
    @State private var showingDelete = false
    @State private var errorMessage: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingTemplateName = false
    @State private var templateName = ""
    @State private var relationKind: TransactionRelationKind?
    @State private var showingAASplitEditor = false
    @State private var showingAASettlement = false
    @State private var showingRemoveAA = false
    @State private var settlementToDelete: AASettlement?

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

    private var aaSplit: AASplit? {
        allAASplits.first { $0.originalTransactionID == transaction.id }
    }

    private var aaSettlements: [AASettlement] {
        guard let splitID = aaSplit?.id else { return [] }
        return allAASettlements.filter { $0.splitID == splitID }
    }

    private var recoverySettlement: AASettlement? {
        allAASettlements.first { $0.recoveryTransactionID == transaction.id }
    }

    private var recoveryOriginal: LedgerTransaction? {
        guard let recoverySettlement,
              let split = allAASplits.first(where: { $0.id == recoverySettlement.splitID }) else { return nil }
        return allTransactions.first { $0.id == split.originalTransactionID }
    }

    private var aaSummary: AASplitSummary? {
        aaSplit.map { AAQueryService().summary(for: $0, settlements: aaSettlements) }
    }

    private var categoryPath: String? {
        guard let category = transaction.category else { return nil }
        guard let parentID = category.parentID,
              let parent = categories.first(where: { $0.id == parentID }) else { return category.name }
        return "\(parent.name) / \(category.name)"
    }

    var body: some View {
        ZStack {
            HomePalette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    TransactionSummaryGlassCard(transaction: transaction, categoryPath: categoryPath)

                    TransactionDetailGlassSection(title: "交易信息", symbol: "list.bullet.rectangle") {
                        DetailValueRow(title: "日期", value: transaction.date.formatted(date: .long, time: .shortened))
                        if let categoryPath { DetailValueRow(title: "分类", value: categoryPath) }
                        if let merchant = transaction.merchantOrCounterparty { DetailValueRow(title: "商户 / 对方", value: merchant) }
                        if let account = transaction.sourceAccount { DetailValueRow(title: "来源账户", value: account.name) }
                        if let code = transaction.sourceCurrencyCode { DetailValueRow(title: "来源币种", value: code) }
                        if let account = transaction.destinationAccount { DetailValueRow(title: "目标账户", value: account.name) }
                        if let code = transaction.destinationCurrencyCode { DetailValueRow(title: "目标币种", value: code) }
                        if let rate = transaction.exchangeRate { DetailValueRow(title: "实际汇率", value: "\(rate)") }
                        if transaction.recognitionImportID != nil { DetailValueRow(title: "来源", value: "截图识别") }
                        if let reason = transaction.adjustmentReason { DetailValueRow(title: "调整原因", value: reason) }
                    }

                    if transaction.paymentParts.count >= 2 || transaction.feeAmount != nil
                        || transaction.originalAmount != nil || transaction.discountAmount != nil {
                        TransactionDetailGlassSection(title: "金额构成", symbol: "sum") {
                            ForEach(transaction.paymentParts.sorted(by: { $0.sortOrder < $1.sortOrder })) { part in
                                DetailValueRow(
                                    title: part.wallet?.account?.name ?? "付款钱包",
                                    value: MoneyFormatter.string(part.amount, currencyCode: part.wallet?.currencyCode ?? transaction.sourceCurrencyCode ?? "CNY")
                                )
                            }
                            if let fee = transaction.feeAmount, fee > 0 {
                                DetailValueRow(title: "手续费", value: MoneyFormatter.string(fee, currencyCode: transaction.feeCurrencyCode ?? "CNY"))
                            }
                            if let original = transaction.originalAmount {
                                DetailValueRow(title: "原价", value: MoneyFormatter.string(original, currencyCode: transaction.currencyCode ?? transaction.sourceCurrencyCode ?? "CNY"))
                            }
                            if let discount = transaction.discountAmount, discount > 0 {
                                DetailValueRow(title: "优惠", value: MoneyFormatter.string(discount, currencyCode: transaction.currencyCode ?? transaction.sourceCurrencyCode ?? "CNY"))
                            }
                        }
                    }

                    if let aaSplit {
                        AASplitDetailCard(
                            split: aaSplit,
                            original: transaction,
                            settlements: aaSettlements,
                            transactions: allTransactions,
                            edit: { showingAASplitEditor = true },
                            remove: { showingRemoveAA = true },
                            record: { showingAASettlement = true },
                            deleteSettlement: { settlementToDelete = $0 }
                        )
                    }

                    if let note = transaction.note, !note.isEmpty {
                        TransactionDetailGlassSection(title: "备注", symbol: "text.alignleft") {
                            Text(note).font(.body).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if recoverySettlement == nil {
                        TransactionDetailGlassSection(title: "图片", symbol: "photo.on.rectangle") {
                            if attachments.isEmpty {
                                Text("尚未添加图片").font(.subheadline).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ScrollView(.horizontal) {
                                    HStack(spacing: 10) {
                                        ForEach(attachments) { attachment in
                                            AttachmentRow(attachment: attachment)
                                                .contextMenu { Button("删除", role: .destructive) { removeAttachment(attachment) } }
                                        }
                                    }
                                }
                                .scrollIndicators(.hidden)
                            }
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Label("添加图片", systemImage: "photo.badge.plus")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }

                    if !relations.isEmpty {
                        TransactionDetailGlassSection(title: "退款与报销", symbol: "arrow.uturn.backward.circle") {
                            ForEach(relations) { relation in
                                HStack(spacing: 10) {
                                    Circle().fill(transaction.type.color).frame(width: 8, height: 8)
                                    Text(relation.kind.title)
                                    Spacer()
                                    Text(MoneyFormatter.string(relation.amount, currencyCode: transaction.sourceCurrencyCode ?? transaction.currencyCode ?? "CNY"))
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                }
                            }
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("交易详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GlassEffectContainer(spacing: 10) {
                Group {
                    if let recoveryOriginal {
                        NavigationLink {
                            TransactionDetailView(transaction: recoveryOriginal)
                        } label: {
                            Label("查看原支出", systemImage: "arrow.uturn.backward")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(HomePalette.accent)
                    } else {
                        HStack(spacing: 10) {
                        Button { showingEdit = true } label: {
                            Label("编辑", systemImage: "pencil")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(HomePalette.accent)

                        Menu {
                            Button("复制记账") { showingCopy = true }
                            Button("保存为模板") {
                                templateName = transaction.merchantOrCounterparty ?? transaction.category?.name ?? transaction.type.title
                                showingTemplateName = true
                            }
                            if transaction.type == .expense {
                                if aaSplit == nil {
                                    Button("发起 AA") { showingAASplitEditor = true }
                                        .disabled(!relations.isEmpty)
                                } else {
                                    Button("编辑 AA 分摊") { showingAASplitEditor = true }
                                    Button("移除 AA", role: .destructive) { showingRemoveAA = true }
                                }
                                Button("记录退款") { relationKind = .refund }
                                    .disabled(aaSplit != nil)
                                Button("记录报销") { relationKind = .reimbursement }
                                    .disabled(aaSplit != nil)
                            }
                            Button("删除交易", role: .destructive) { showingDelete = true }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.headline).frame(width: 52, height: 48)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel("更多交易操作")
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .sheet(isPresented: $showingEdit) {
            TransactionEditView(transaction: transaction) { dismiss() }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingCopy) {
            EntryView(
                seed: TransactionDraft(transaction: transaction),
                dismissAfterSave: true
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $relationKind) { kind in
            TransactionRelationEntryView(
                original: transaction,
                kind: kind,
                wallets: relationWallets
            )
        }
        .sheet(isPresented: $showingAASplitEditor) {
            AASplitEditorView(
                totalAmount: transaction.sourceAmount ?? transaction.amount ?? 0,
                currencyCode: transaction.sourceCurrencyCode ?? transaction.currencyCode ?? SupportedCurrency.CNY.rawValue,
                initialDraft: aaSplit.map {
                    AASplitDraft(
                        split: $0,
                        totalAmount: transaction.sourceAmount ?? transaction.amount ?? 0
                    )
                }
            ) { draft in
                try AASplitService(context: context).upsert(draft, for: transaction)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAASettlement) {
            if let aaSplit, let aaSummary {
                AASettlementEntryView(
                    split: aaSplit,
                    original: transaction,
                    remainingAmount: aaSummary.remainingAmount,
                    wallets: relationWallets
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .confirmationDialog("确定删除这笔交易？", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("删除并回滚余额", role: .destructive, action: deleteTransaction)
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("移除这笔 AA 分摊？", isPresented: $showingRemoveAA, titleVisibility: .visible) {
            Button("移除 AA", role: .destructive, action: removeAASplit)
            Button("取消", role: .cancel) {}
        } message: {
            Text("移除后，这笔支出会重新按实付全额计入消费和预算。")
        }
        .confirmationDialog(
            "删除这条 AA 收款？",
            isPresented: Binding(
                get: { settlementToDelete != nil },
                set: { if !$0 { settlementToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除并扣回账户余额", role: .destructive, action: deleteAASettlement)
            Button("取消", role: .cancel) { settlementToDelete = nil }
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
            Text("模板会保存当前交易的账户、分类和金额，使用时仍需确认后入账。")
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

    private func removeAASplit() {
        do {
            try AASplitService(context: context).remove(from: transaction)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAASettlement() {
        guard let settlement = settlementToDelete else { return }
        do {
            try AASettlementService(context: context).delete(settlement)
            settlementToDelete = nil
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

private struct TransactionSummaryGlassCard: View {
    let transaction: LedgerTransaction
    let categoryPath: String?

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: transaction.category?.symbolName ?? transaction.type.symbolName)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(transaction.type.color)
                .frame(width: 52, height: 52)
                .background(transaction.type.color.opacity(0.11), in: Circle())
            Text(transaction.summaryAmount)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.64)
            Text(categoryPath ?? transaction.type.title)
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 6) {
                Text(transaction.type.title)
                Text("·")
                Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22).padding(.horizontal, 18)
        .ledgerGlassCard(cornerRadius: 30, tint: transaction.type.color)
    }
}

private struct TransactionDetailGlassSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(HomePalette.accent)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .ledgerGlassCard(cornerRadius: 24)
    }
}

private struct DetailValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).font(.subheadline.weight(.medium)).multilineTextAlignment(.trailing)
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
