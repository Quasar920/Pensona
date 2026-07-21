import SwiftData
import SwiftUI

struct AASplitEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let totalAmount: Decimal
    let currencyCode: String
    let initialDraft: AASplitDraft?
    let save: (AASplitDraft) throws -> Void

    @State private var totalPeopleText: String
    @State private var customOthersOwedText: String
    @State private var note: String
    @State private var errorMessage: String?

    private let calculator = AASplitCalculator()

    init(
        totalAmount: Decimal,
        currencyCode: String,
        initialDraft: AASplitDraft?,
        save: @escaping (AASplitDraft) throws -> Void
    ) {
        self.totalAmount = totalAmount
        self.currencyCode = currencyCode
        self.initialDraft = initialDraft
        self.save = save
        _totalPeopleText = State(initialValue: initialDraft.map { String($0.otherPeopleCount + 1) } ?? "2")
        _customOthersOwedText = State(initialValue: initialDraft.map {
            NSDecimalNumber(decimal: $0.othersOwedAmount).stringValue
        } ?? "")
        _note = State(initialValue: initialDraft?.note ?? "")
    }

    private var preview: AASplitAmounts? {
        guard let totalPeople = Int(totalPeopleText), totalPeople >= 2 else { return nil }
        let count = totalPeople - 1
        let customAmount = DecimalParser.parse(customOthersOwedText) ?? 0
        return try? calculator.amounts(
            totalAmount: totalAmount,
            otherPeopleCount: count,
            mode: initialDraft?.calculationMode == .custom ? .custom : .equal,
            customOthersOwedAmount: customAmount,
            currencyCode: currencyCode
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomePalette.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("本次实付")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(MoneyFormatter.string(totalAmount, currencyCode: currencyCode))
                                .font(.system(size: 34, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .ledgerGlassCard(cornerRadius: 24)

                        HStack(spacing: 10) {
                            Text("总人数（包含自己）")
                                .font(.headline)
                            TextField("人数", text: $totalPeopleText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .frame(width: 72, height: 44)
                                .background(HomePalette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                            Text("人")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(16)
                        .ledgerGlassCard(cornerRadius: 22)

                        VStack(alignment: .leading, spacing: 12) {
                            Text(
                                initialDraft?.calculationMode == .custom
                                    ? AppLocalization.string("历史自定义分摊")
                                    : AppLocalization.string("按总人数均分")
                            )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if initialDraft?.calculationMode == .custom {
                                HStack {
                                    Text("其他人合计应还")
                                    Spacer()
                                    Text(currencyCode)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                    TextField("0", text: $customOthersOwedText)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .font(.headline.monospacedDigit())
                                        .frame(width: 110)
                                }
                            }

                            Divider().opacity(0.45)
                            amountRow("其他人合计应还", amount: preview?.othersOwedAmount)
                            amountRow("我的承担", amount: preview?.myShareAmount)
                        }
                        .padding(16)
                        .ledgerGlassCard(cornerRadius: 22)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("备注")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            TextField("例如：小王、小李；聚餐 AA", text: $note, axis: .vertical)
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
            .navigationTitle("AA 分摊")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: validateAndSave)
                        .fontWeight(.semibold)
                }
            }
            .onChange(of: totalPeopleText) { _, _ in errorMessage = nil }
            .onChange(of: customOthersOwedText) { _, _ in errorMessage = nil }
        }
    }

    private func amountRow(_ title: String, amount: Decimal?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(amount.map { MoneyFormatter.string($0, currencyCode: currencyCode) } ?? "--")
                .font(.headline.monospacedDigit())
        }
    }

    private func validateAndSave() {
        do {
            guard let totalPeople = Int(totalPeopleText), totalPeople >= 2 else {
                throw AASplitError.invalidOtherPeopleCount
            }
            let count = totalPeople - 1
            let customAmount = DecimalParser.parse(customOthersOwedText) ?? 0
            let mode: AASplitCalculationMode = initialDraft?.calculationMode == .custom ? .custom : .equal
            let raw = AASplitDraft(
                otherPeopleCount: count,
                calculationMode: mode,
                othersOwedAmount: customAmount,
                note: note,
                basedOnAmount: totalAmount
            )
            let resolved = try calculator.resolvedDraft(
                raw,
                totalAmount: totalAmount,
                currencyCode: currencyCode
            )
            try save(resolved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AASettlementEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let split: AASplit
    let original: LedgerTransaction
    let remainingAmount: Decimal
    let wallets: [CurrencyWallet]

    @State private var amountText: String
    @State private var walletID: UUID?
    @State private var date = Date.now
    @State private var note = ""
    @State private var errorMessage: String?

    init(
        split: AASplit,
        original: LedgerTransaction,
        remainingAmount: Decimal,
        wallets: [CurrencyWallet]
    ) {
        self.split = split
        self.original = original
        self.remainingAmount = remainingAmount
        self.wallets = wallets
        _amountText = State(initialValue: NSDecimalNumber(decimal: remainingAmount).stringValue)
        _walletID = State(initialValue: wallets.first?.id)
    }

    private var currencyCode: String {
        original.sourceCurrencyCode ?? original.currencyCode ?? SupportedCurrency.CNY.rawValue
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("剩余待收") {
                    Text(MoneyFormatter.string(remainingAmount, currencyCode: currencyCode))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Section("本次收款") {
                    HStack {
                        Text(currencyCode).foregroundStyle(.secondary)
                        TextField("收款金额", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.title3.weight(.semibold).monospacedDigit())
                    }
                    Picker("收款账户", selection: $walletID) {
                        ForEach(wallets) { wallet in
                            Text("\(wallet.account?.name ?? AppLocalization.string("未知账户")) · \(wallet.currencyCode)")
                                .tag(wallet.id as UUID?)
                        }
                    }
                    DatePicker("到账日期", selection: $date)
                    TextField("备注，例如：小王已还", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(HomePalette.expense)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(HomePalette.background)
            .navigationTitle("记录 AA 收款")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认收款", action: saveRecord)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func saveRecord() {
        do {
            guard let amount = DecimalParser.parse(amountText) else {
                throw AASplitError.settlementAmountInvalid
            }
            guard let wallet = wallets.first(where: { $0.id == walletID }) else {
                throw AASplitError.walletUnavailable
            }
            _ = try AASettlementService(context: context).record(
                split: split,
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

private struct AASettlementDisplay: Identifiable {
    let settlement: AASettlement
    let transaction: LedgerTransaction
    var id: UUID { settlement.id }
}

struct AASplitDetailCard: View {
    let split: AASplit
    let original: LedgerTransaction
    let settlements: [AASettlement]
    let transactions: [LedgerTransaction]
    let edit: () -> Void
    let remove: () -> Void
    let record: () -> Void
    let deleteSettlement: (AASettlement) -> Void

    private var currencyCode: String {
        original.sourceCurrencyCode ?? original.currencyCode ?? SupportedCurrency.CNY.rawValue
    }

    private var summary: AASplitSummary {
        AAQueryService().summary(for: split, settlements: settlements)
    }

    private var history: [AASettlementDisplay] {
        let byID = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        return settlements.compactMap { settlement in
            byID[settlement.recoveryTransactionID].map {
                AASettlementDisplay(settlement: settlement, transaction: $0)
            }
        }
        .sorted { $0.transaction.date > $1.transaction.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("AA 分摊", systemImage: "person.2.fill")
                    .font(.headline)
                Spacer()
                Text(summary.status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HomePalette.accent)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(HomePalette.accent.opacity(0.09), in: Capsule())
                Menu {
                    Button("编辑分摊", action: edit)
                    Button("移除 AA", role: .destructive, action: remove)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                }
            }

            Text("我和其他 \(split.otherPeopleCount) 人 · \(split.calculationMode.title)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            detailRow("我的承担", originalAmount - split.othersOwedAmount)
            detailRow("已收", summary.collectedAmount)
            detailRow("待收", summary.remainingAmount)

            ProgressView(value: summary.progress)
                .tint(HomePalette.accent)

            if let note = split.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if summary.remainingAmount > 0 {
                Button(action: record) {
                    Label("记录收款", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.glassProminent)
                .tint(HomePalette.accent)
            }

            if !history.isEmpty {
                Divider().opacity(0.45)
                Text("收款历史")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(history) { item in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.transaction.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline.weight(.medium))
                            Text(item.transaction.note ?? item.transaction.sourceAccount?.name ?? AppLocalization.string("AA 收回"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(MoneyFormatter.string(item.settlement.amount, currencyCode: currencyCode))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                        Button(role: .destructive) {
                            deleteSettlement(item.settlement)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除这条 AA 收款")
                    }
                }
            }
        }
        .padding(16)
        .ledgerGlassCard(cornerRadius: 24)
        .accessibilityElement(children: .contain)
    }

    private var originalAmount: Decimal {
        original.sourceAmount ?? original.amount ?? 0
    }

    private func detailRow(_ title: String, _ amount: Decimal) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(MoneyFormatter.string(amount, currencyCode: currencyCode))
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }
}

struct AAReceivableHomeCard: View {
    let overview: AAReceivableOverview
    let currencyCode: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                Image(systemName: "person.2.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(HomePalette.accent)
                    .frame(width: 42, height: 42)
                    .background(HomePalette.accent.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("AA 待收")
                        .font(.subheadline.weight(.semibold))
                    Text(overview.missingCodes.isEmpty
                         ? MoneyFormatter.string(overview.amount, currencyCode: currencyCode)
                         : AppLocalization.string("部分币种缺少汇率"))
                        .font(.title3.weight(.semibold).monospacedDigit())
                }
                Spacer()
                Text("共 \(overview.openCount) 笔")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(15)
            .contentShape(Rectangle())
        }
        .buttonStyle(LedgerGlassPressStyle())
        .ledgerGlassCard(cornerRadius: 22)
        .accessibilityLabel("AA 待收，\(overview.openCount) 笔")
    }
}

struct AAReceivableListView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LedgerTransaction.date, order: .reverse) private var transactions: [LedgerTransaction]
    @Query private var splits: [AASplit]
    @Query private var settlements: [AASettlement]

    let bookID: UUID
    @State private var showsSettled = false

    private var items: [AAReceivableItem] {
        AAQueryService().items(
            splits: splits,
            settlements: settlements,
            transactions: transactions,
            bookID: bookID
        )
        .filter { showsSettled ? $0.summary.status == .settled : $0.summary.status != .settled }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomePalette.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        Picker("AA 状态", selection: $showsSettled) {
                            Text("待收").tag(false)
                            Text("已结清").tag(true)
                        }
                        .pickerStyle(.segmented)

                        if items.isEmpty {
                            ContentUnavailableView(
                                showsSettled
                                    ? AppLocalization.string("还没有已结清的 AA")
                                    : AppLocalization.string("没有待收 AA"),
                                systemImage: showsSettled ? "checkmark.circle" : "person.2"
                            )
                            .padding(.top, 50)
                        } else {
                            ForEach(items) { item in
                                NavigationLink {
                                    TransactionDetailView(transaction: item.transaction)
                                } label: {
                                    aaRow(item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("AA 待收")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func aaRow(_ item: AAReceivableItem) -> some View {
        let code = item.transaction.sourceCurrencyCode
            ?? item.transaction.currencyCode
            ?? SupportedCurrency.CNY.rawValue
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(item.transaction.merchantOrCounterparty
                     ?? item.transaction.category?.name
                     ?? item.transaction.note
                     ?? AppLocalization.string("AA 支出"))
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(item.summary.status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HomePalette.accent)
            }
            Text("我和其他 \(item.split.otherPeopleCount) 人 · \(item.split.calculationMode.title)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text("待收 \(MoneyFormatter.string(item.summary.remainingAmount, currencyCode: code))")
                Spacer()
                Text("应收 \(MoneyFormatter.string(item.summary.othersOwedAmount, currencyCode: code))")
            }
            .font(.subheadline.weight(.semibold).monospacedDigit())
            ProgressView(value: item.summary.progress)
                .tint(HomePalette.accent)
            if let note = item.split.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(15)
        .ledgerGlassCard(cornerRadius: 22)
    }
}
