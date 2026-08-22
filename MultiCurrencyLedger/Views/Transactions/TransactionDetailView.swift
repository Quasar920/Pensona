import SwiftData
import SwiftUI
import PhotosUI
import UIKit
import CoreTransferable
import UniformTypeIdentifiers

@MainActor
enum TransactionNoteUpdater {
    static func update(
        _ note: String,
        transaction: LedgerTransaction,
        context: ModelContext
    ) throws {
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.note = cleanNote.isEmpty ? nil : cleanNote
        transaction.updatedAt = .now
        try context.save()
        NotificationCenter.default.post(name: .ledgerTransactionsDidChange, object: nil)
    }
}

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
    @State private var showingNoteEditor = false
    @State private var showingAttachments = false
    @State private var showingCopy = false
    @State private var showingDelete = false
    @State private var errorMessage: String?
    @State private var showingTemplateName = false
    @State private var templateName = ""
    @State private var relationKind: TransactionRelationKind?
    @State private var showingAASplitEditor = false
    @State private var showingAASettlement = false
    @State private var showingRemoveAA = false
    @State private var settlementToDelete: AASettlement?

    private let actionColumns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: 3
    )

    private var attachments: [TransactionAttachment] {
        allAttachments.filter { $0.transactionID == transaction.id }
    }

    private var relations: [TransactionRelation] {
        allRelations.filter { $0.originalTransactionID == transaction.id }
    }

    private var relationWallets: [CurrencyWallet] {
        let currencyCode = transaction.sourceCurrencyCode ?? transaction.currencyCode
        return accounts
            .filter { !$0.isArchived }
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
                    TransactionDetailGlassSection(title: AppLocalization.string("交易信息"), symbol: "list.bullet.rectangle") {
                        DetailValueRow(title: AppLocalization.string("日期"), value: transaction.date.formatted(date: .long, time: .shortened))
                        if let categoryPath { DetailValueRow(title: AppLocalization.string("分类"), value: categoryPath) }
                        if let merchant = transaction.merchantOrCounterparty { DetailValueRow(title: AppLocalization.string("商户 / 对方"), value: merchant) }
                        if let account = transaction.sourceAccount { DetailValueRow(title: AppLocalization.string("来源账户"), value: account.name) }
                        if let code = transaction.sourceCurrencyCode ?? transaction.currencyCode {
                            DetailValueRow(title: AppLocalization.string("币种"), value: code)
                        }
                        if let account = transaction.destinationAccount { DetailValueRow(title: AppLocalization.string("目标账户"), value: account.name) }
                        if let code = transaction.destinationCurrencyCode { DetailValueRow(title: AppLocalization.string("目标币种"), value: code) }
                        if let rate = transaction.exchangeRate { DetailValueRow(title: AppLocalization.string("实际汇率"), value: "\(rate)") }
                        if let rate = transaction.settlementExchangeRate {
                            DetailValueRow(title: "结算实际汇率", value: "\(rate)")
                        }
                        if let rate = transaction.referenceExchangeRate {
                            DetailValueRow(title: "参考汇率", value: "\(rate)")
                        }
                        if let mode = transaction.foreignSettlementMode {
                            DetailValueRow(title: "外币结算方式", value: mode.title)
                        }
                        if let originalAmount = transaction.foreignOriginalAmount,
                           let code = transaction.foreignOriginalCurrencyCode {
                            DetailValueRow(
                                title: "外币原始金额",
                                value: MoneyFormatter.string(originalAmount, currencyCode: code)
                            )
                        }
                        if let settledAmount = transaction.settledAmount,
                           let code = transaction.settlementCurrencyCode {
                            DetailValueRow(
                                title: "结算金额",
                                value: MoneyFormatter.string(settledAmount, currencyCode: code)
                            )
                        }
                        if let index = transaction.installmentIndex {
                            DetailValueRow(title: "分期期次", value: "第 \(index + 1) 期")
                        }
                        if transaction.recognitionImportID != nil { DetailValueRow(title: AppLocalization.string("来源"), value: AppLocalization.string("截图识别")) }
                        if let reason = transaction.adjustmentReason { DetailValueRow(title: AppLocalization.string("调整原因"), value: reason) }
                        EditableTransactionNoteRow(note: transaction.note) {
                            showingNoteEditor = true
                        }
                    }

                    if transaction.paymentParts.count >= 2 || transaction.feeAmount != nil
                        || transaction.originalAmount != nil || transaction.discountAmount != nil {
                        TransactionDetailGlassSection(title: AppLocalization.string("金额构成"), symbol: "sum") {
                            ForEach(transaction.paymentParts.sorted(by: { $0.sortOrder < $1.sortOrder })) { part in
                                DetailValueRow(
                                    title: part.wallet?.account?.name ?? AppLocalization.string("付款钱包"),
                                    value: MoneyFormatter.string(part.amount, currencyCode: part.wallet?.currencyCode ?? transaction.sourceCurrencyCode ?? "CNY")
                                )
                            }
                            if let fee = transaction.feeAmount, fee > 0 {
                                DetailValueRow(title: AppLocalization.string("手续费"), value: MoneyFormatter.string(fee, currencyCode: transaction.feeCurrencyCode ?? "CNY"))
                                if let wallet = transaction.feeWallet {
                                    DetailValueRow(
                                        title: "手续费账户",
                                        value: "\(wallet.account?.name ?? AppLocalization.string("未知账户")) · \(wallet.currencyCode)"
                                    )
                                }
                            }
                            if let original = transaction.originalAmount {
                                DetailValueRow(
                                    title: transaction.type == .income && transaction.feeAmount != nil
                                        ? "手续费前金额"
                                        : AppLocalization.string("原价"),
                                    value: MoneyFormatter.string(
                                        original,
                                        currencyCode: transaction.currencyCode
                                            ?? transaction.sourceCurrencyCode
                                            ?? "CNY"
                                    )
                                )
                            }
                            if let discount = transaction.discountAmount, discount > 0 {
                                DetailValueRow(
                                    title: AppLocalization.string("优惠"),
                                    value: MoneyFormatter.string(
                                        discount,
                                        currencyCode: transaction.discountCurrencyCode
                                            ?? transaction.currencyCode
                                            ?? transaction.sourceCurrencyCode
                                            ?? "CNY"
                                    )
                                )
                                if let wallet = transaction.discountWallet {
                                    DetailValueRow(
                                        title: "优惠账户",
                                        value: "\(wallet.account?.name ?? AppLocalization.string("未知账户")) · \(wallet.currencyCode)"
                                    )
                                }
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

                    if let recoveryOriginal {
                        NavigationLink {
                            TransactionDetailView(transaction: recoveryOriginal)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.uturn.backward")
                                Text("查看原支出")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(HomePalette.accent)
                            .padding(16)
                            .ledgerGlassCard(cornerRadius: 24)
                        }
                        .buttonStyle(LedgerGlassPressStyle())
                    }

                    if !relations.isEmpty {
                        TransactionDetailGlassSection(title: AppLocalization.string("退款与报销"), symbol: "arrow.uturn.backward.circle") {
                            ForEach(relations) { relation in
                                if relation.amount > 0 {
                                    HStack(spacing: 10) {
                                        Circle().fill(transaction.type.color).frame(width: 8, height: 8)
                                        Text(relation.kind.title)
                                        Spacer()
                                        Text(MoneyFormatter.string(relation.amount, currencyCode: transaction.sourceCurrencyCode ?? transaction.currencyCode ?? "CNY"))
                                            .font(.subheadline.weight(.semibold).monospacedDigit())
                                    }
                                }
                                if let excessIncomeAmount = relation.excessIncomeAmount, excessIncomeAmount > 0 {
                                    HStack(spacing: 10) {
                                        Circle().fill(transaction.type.color).frame(width: 8, height: 8)
                                        Text(relation.kind == .refund ? "退款收入" : "自动其他收入")
                                        Spacer()
                                        Text(MoneyFormatter.string(excessIncomeAmount, currencyCode: transaction.sourceCurrencyCode ?? transaction.currencyCode ?? "CNY"))
                                            .font(.subheadline.weight(.semibold).monospacedDigit())
                                    }
                                }
                            }
                        }
                    }

                    LazyVGrid(columns: actionColumns, spacing: 10) {
                        TransactionDetailActionTile(title: "图片", symbol: "photo.badge.plus") {
                            showingAttachments = true
                        }
                        .disabled(recoverySettlement != nil)
                        .opacity(recoverySettlement == nil ? 1 : 0.42)

                        TransactionDetailActionTile(title: "报销", symbol: "doc.text") {
                            relationKind = .reimbursement
                        }
                        .disabled(!canRecordRecovery)
                        .opacity(canRecordRecovery ? 1 : 0.42)

                        TransactionDetailActionTile(title: "退款", symbol: "arrow.uturn.backward.circle") {
                            relationKind = .refund
                        }
                        .disabled(!canRecordRecovery)
                        .opacity(canRecordRecovery ? 1 : 0.42)

                        TransactionDetailActionTile(title: "AA 分摊", symbol: "person.2") {
                            showingAASplitEditor = true
                        }
                        .disabled(!canOpenAASplit)
                        .opacity(canOpenAASplit ? 1 : 0.42)

                        TransactionDetailActionTile(title: "保存为模板", symbol: "bookmark") {
                            prepareTemplate()
                        }

                        TransactionDetailActionTile(title: "复制记账", symbol: "doc.on.doc") {
                            showingCopy = true
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("交易详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 10) {
                Button { showingEdit = true } label: {
                    Label("编辑", systemImage: "pencil")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(TransactionDetailPillButtonStyle(tint: HomePalette.accent))

                Button(role: .destructive) { showingDelete = true } label: {
                    Label("删除", systemImage: "trash")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(TransactionDetailPillButtonStyle(tint: .red))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingEdit) {
            TransactionEditView(transaction: transaction) {}
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingNoteEditor) {
            TransactionNoteEditor(note: transaction.note ?? "") { note in
                try updateNote(note)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAttachments) {
            TransactionAttachmentManager(
                attachments: attachments,
                importPhoto: importPhoto,
                remove: removeAttachment
            )
            .presentationDetents([.medium, .large])
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
                wallets: relationWallets,
                onSaved: {
                    guard kind == .refund else { return }
                    relationKind = nil
                    dismiss()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
        )) { Button("好") {} } message: { Text(errorMessage ?? AppLocalization.string("未知错误")) }
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
    private func importPhoto(_ item: PhotosPickerItem) async throws {
        guard let photo = try await item.loadTransferable(type: ImportedTransactionPhoto.self) else {
            throw AttachmentError.emptyData
        }
        try AttachmentService(context: context).addImage(data: photo.data, to: transaction)
    }

    private func removeAttachment(_ attachment: TransactionAttachment) {
        do {
            try AttachmentService(context: context).remove(attachment)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var canRecordRecovery: Bool {
        transaction.type == .expense && aaSplit == nil
    }

    private var canOpenAASplit: Bool {
        transaction.type == .expense && (aaSplit != nil || relations.isEmpty)
    }

    private func updateNote(_ note: String) throws {
        try TransactionNoteUpdater.update(note, transaction: transaction, context: context)
    }

    private func prepareTemplate() {
        templateName = transaction.merchantOrCounterparty ?? transaction.category?.name ?? transaction.type.title
        showingTemplateName = true
    }

    private func saveAsTemplate() {
        do {
            guard let bookID = transaction.bookID else { throw LedgerError.missingBook }
            try TransactionTemplateService(context: context).create(
                name: templateName,
                bookID: bookID,
                from: TransactionDraft(transaction: transaction)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
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

private struct EditableTransactionNoteRow: View {
    let note: String?
    let edit: () -> Void

    private var cleanNote: String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("备注")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            if let cleanNote {
                Button(action: edit) {
                    Text(cleanNote)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .underline(pattern: .solid, color: .primary)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .accessibilityLabel("备注")
            } else {
                Button(action: edit) {
                    VStack(spacing: 2) {
                        Image(systemName: "pencil")
                            .font(.subheadline.weight(.medium))
                        Capsule()
                            .fill(Color.primary)
                            .frame(width: 18, height: 1)
                    }
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
                }
                .buttonStyle(LedgerGlassPressStyle())
                .accessibilityLabel("备注")
            }
        }
    }
}

private struct TransactionDetailActionTile: View {
    let title: LocalizedStringKey
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    VStack(spacing: 10) {
                        Image(systemName: symbol)
                            .font(.system(size: 25, weight: .medium))
                            .frame(height: 30)
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(HomePalette.accent)
                    .padding(10)
                }
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .ledgerGlassCard(cornerRadius: 22)
        }
        .buttonStyle(LedgerGlassPressStyle())
    }
}

private struct TransactionDetailPillButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(tint, lineWidth: 1.2))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(LedgerMotion.press(isPressed: configuration.isPressed), value: configuration.isPressed)
    }
}

private struct TransactionNoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (String) throws -> Void
    @State private var note: String
    @State private var errorMessage: String?
    @FocusState private var noteIsFocused: Bool

    init(note: String, onSave: @escaping (String) throws -> Void) {
        _note = State(initialValue: note)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomePalette.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 8) {
                    Text("备注")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextEditor(text: $note)
                        .focused($noteIsFocused)
                        .accessibilityLabel("备注")
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("删除", role: .destructive) {
                            commit("")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }
            .navigationTitle("备注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { commit(note) }
                }
            }
            .alert("操作失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(errorMessage ?? AppLocalization.string("未知错误"))
            }
            .task {
                await Task.yield()
                noteIsFocused = true
            }
        }
    }

    private func commit(_ value: String) {
        do {
            try onSave(value)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ImportedTransactionPhoto: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            ImportedTransactionPhoto(data: data)
        }
    }
}

private struct TransactionAttachmentManager: View {
    @Environment(\.dismiss) private var dismiss
    let attachments: [TransactionAttachment]
    let importPhoto: (PhotosPickerItem) async throws -> Void
    let remove: (TransactionAttachment) -> Void
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                HomePalette.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            HStack(spacing: 12) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.title2.weight(.semibold))
                                    .frame(width: 44, height: 44)
                                    .background(HomePalette.accent.opacity(0.10), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("添加图片")
                                        .font(.headline)
                                }
                                Spacer()
                                if isImporting {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(HomePalette.accent)
                            .padding(16)
                            .ledgerGlassCard(cornerRadius: 22)
                        }
                        .buttonStyle(LedgerGlassPressStyle())
                        .disabled(isImporting)

                        if attachments.isEmpty {
                            VStack {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 30, weight: .medium))
                                    .foregroundStyle(HomePalette.accent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                            .ledgerGlassCard(cornerRadius: 22)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(attachments) { attachment in
                                    HStack(spacing: 12) {
                                        AttachmentRow(attachment: attachment)
                                        Spacer(minLength: 8)
                                        Button(role: .destructive) {
                                            remove(attachment)
                                        } label: {
                                            Image(systemName: "trash")
                                                .frame(width: 36, height: 36)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("删除")
                                    }
                                    if attachment.id != attachments.last?.id {
                                        Divider().opacity(0.45)
                                    }
                                }
                            }
                            .padding(16)
                            .ledgerGlassCard(cornerRadius: 22)
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("图片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Text("添加图片")
                            .fontWeight(.semibold)
                    }
                    .disabled(isImporting)
                }
            }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                isImporting = true
                defer {
                    isImporting = false
                    self.selectedPhoto = nil
                }
                do {
                    try await importPhoto(selectedPhoto)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .alert("操作失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") {}
            } message: {
                Text(errorMessage ?? AppLocalization.string("未知错误"))
            }
        }
    }
}

struct TransactionRelationEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let original: LedgerTransaction
    let kind: TransactionRelationKind
    let wallets: [CurrencyWallet]
    let onSaved: (() -> Void)?
    @State private var amountText = ""
    @State private var walletID: UUID?
    @State private var date = Date.now
    @State private var note = ""
    @State private var remaining: Decimal = 0
    @State private var errorMessage: String?

    private var enteredAmount: Decimal {
        DecimalParser.parse(amountText) ?? 0
    }

    private var automaticOtherIncomeAmount: Decimal {
        max(0, enteredAmount - remaining)
    }

    private var isRefund: Bool { kind == .refund }

    var body: some View {
        NavigationStack {
            ZStack {
                HomePalette.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(kind.title)金额")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(original.sourceCurrencyCode ?? original.currencyCode ?? "CNY")
                                    .font(.title3.weight(.semibold).monospaced())
                                    .foregroundStyle(.secondary)
                                TextField("0", text: $amountText)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                                    .multilineTextAlignment(.trailing)
                            }
                            Text(isRefund
                                ? "尚可记为退款 \(MoneyFormatter.string(remaining, currencyCode: original.sourceCurrencyCode ?? original.currencyCode ?? "CNY"))"
                                : "尚可冲减原支出 \(MoneyFormatter.string(remaining, currencyCode: original.sourceCurrencyCode ?? original.currencyCode ?? "CNY"))"
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            if automaticOtherIncomeAmount > 0 {
                                Text(isRefund
                                    ? "其中 \(MoneyFormatter.string(automaticOtherIncomeAmount, currencyCode: original.sourceCurrencyCode ?? original.currencyCode ?? "CNY")) 将自动记为其他收入 > 退款收入"
                                    : "其中 \(MoneyFormatter.string(automaticOtherIncomeAmount, currencyCode: original.sourceCurrencyCode ?? original.currencyCode ?? "CNY")) 将自动记为其他收入 > 其他收入兜底"
                                )
                                .font(.footnote)
                                .foregroundStyle(HomePalette.accent)
                            }
                        }
                        .padding(18)
                        .ledgerGlassCard(cornerRadius: 24)

                        VStack(spacing: 0) {
                            Picker("入账钱包", selection: $walletID) {
                                ForEach(wallets) { wallet in
                                    Text("\(wallet.account?.name ?? AppLocalization.string("账户")) / \(wallet.currencyCode)")
                                        .tag(wallet.id as UUID?)
                                }
                            }
                            .frame(minHeight: 48)

                            Divider().opacity(0.45)

                            DatePicker("日期", selection: $date)
                                .frame(minHeight: 48)
                        }
                        .padding(.horizontal, 16)
                        .ledgerGlassCard(cornerRadius: 22)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("备注")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("可选", text: $note, axis: .vertical)
                                .lineLimit(2...4)
                                .textFieldStyle(.plain)
                        }
                        .padding(16)
                        .ledgerGlassCard(cornerRadius: 22)

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(HomePalette.expense)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: save)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                walletID = wallets.first?.id
                remaining = (try? TransactionRelationService(context: context).summary(for: original).remaining) ?? 0
                amountText = NSDecimalNumber(decimal: remaining).stringValue
            }
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
            if kind == .refund {
                DispatchQueue.main.async { onSaved?() }
            }
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
