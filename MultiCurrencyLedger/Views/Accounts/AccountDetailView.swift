import SwiftData
import SwiftUI

struct AccountDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerTransaction.date, order: .reverse) private var transactions: [LedgerTransaction]
    let account: Account
    @State private var showingAddWallet = false
    @State private var showingEdit = false
    @State private var errorMessage: String?

    private var accountTransactions: [LedgerTransaction] {
        transactions.filter { $0.sourceAccount === account || $0.destinationAccount === account }
    }

    var body: some View {
        List {
            Section("账户信息") {
                LabeledContent("类型", value: account.type.assetGroup.title)
                if let note = account.note, !note.isEmpty {
                    LabeledContent("备注", value: note)
                }
                LabeledContent("状态", value: account.isArchived ? "已归档" : (account.isHidden ? "已隐藏" : "正常"))
            }

            Section {
                if account.allWallets.isEmpty {
                    Text("尚未添加币种").foregroundStyle(.secondary)
                } else {
                    ForEach(account.allWallets) { wallet in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                            VStack(alignment: .leading) {
                                Text(wallet.currencyCode).font(.headline)
                                Text((wallet.currency?.localizedName ?? wallet.currencyCode) + (wallet.isEnabled ? "" : " · 已停用"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(MoneyFormatter.string(wallet.balance, currencyCode: wallet.currencyCode))
                                .monospacedDigit()
                            }
                            HStack {
                                reconciliationLabel(for: wallet)
                                Spacer()
                                Button(wallet.isEnabled ? "停用" : "恢复") { toggleWallet(wallet) }
                                    .buttonStyle(.bordered)
                                if wallet.balance == 0 {
                                    Button("删除", role: .destructive) { deleteWallet(wallet) }
                                        .buttonStyle(.bordered)
                                }
                                if let result = try? reconciliation(for: wallet), !result.isBalanced {
                                    Button("按流水重算") { rebuild(wallet) }
                                        .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("币种钱包")
                    Spacer()
                    Button("添加币种") { showingAddWallet = true }
                        .textCase(nil)
                }
            }

            Section("最近交易") {
                if accountTransactions.isEmpty {
                    Text("暂无交易").foregroundStyle(.secondary)
                } else {
                    ForEach(accountTransactions.prefix(10)) { transaction in
                        TransactionCompactRow(transaction: transaction)
                    }
                }
            }
        }
        .navigationTitle(account.name)
        .toolbar {
            Menu {
                Button("编辑账户") { showingEdit = true }
                Button(account.isArchived ? "恢复账户" : "归档账户") { toggleArchive() }
                if accountTransactions.isEmpty {
                    Button("删除账户", role: .destructive) { deleteAccount() }
                }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .sheet(isPresented: $showingAddWallet) {
            AddWalletView(account: account)
        }
        .sheet(isPresented: $showingEdit) {
            AccountEditView(account: account)
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
    }

    @ViewBuilder
    private func reconciliationLabel(for wallet: CurrencyWallet) -> some View {
        if let result = try? reconciliation(for: wallet) {
            if result.isBalanced {
                Label("流水一致", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Label(
                    "差异 \(MoneyFormatter.plain(result.difference, currencyCode: wallet.currencyCode))",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func reconciliation(for wallet: CurrencyWallet) throws -> WalletReconciliationResult {
        try BalanceReconciliationService(context: context).result(
            for: wallet,
            transactions: transactions
        )
    }

    private func toggleWallet(_ wallet: CurrencyWallet) {
        do { try AccountService(context: context).setWalletEnabled(!wallet.isEnabled, wallet: wallet) }
        catch { errorMessage = error.localizedDescription }
    }

    private func rebuild(_ wallet: CurrencyWallet) {
        do { try BalanceReconciliationService(context: context).rebuild(wallet, transactions: transactions) }
        catch { errorMessage = error.localizedDescription }
    }

    private func deleteWallet(_ wallet: CurrencyWallet) {
        do { try AccountService(context: context).deleteWallet(wallet, transactions: transactions) }
        catch { errorMessage = error.localizedDescription }
    }

    private func deleteAccount() {
        do {
            try AccountService(context: context).deleteAccount(account, transactions: transactions)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func toggleArchive() {
        do {
            try AccountService(context: context).setArchived(!account.isArchived, account: account)
            if account.isArchived { dismiss() }
        } catch { errorMessage = error.localizedDescription }
    }
}

struct AccountEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let account: Account
    @State private var name: String
    @State private var type: AccountType
    @State private var note: String
    @State private var sortOrder: Int
    @State private var isHidden: Bool
    @State private var cardLastFour: String
    @State private var errorMessage: String?

    init(account: Account) {
        self.account = account
        _name = State(initialValue: account.name)
        _type = State(initialValue: account.type)
        _note = State(initialValue: account.note ?? "")
        _sortOrder = State(initialValue: account.sortOrder)
        _isHidden = State(initialValue: account.isHidden)
        _cardLastFour = State(initialValue: AccountCardIdentityStore().lastFour(for: account.id) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("账户名称", text: $name)
                Picker("账户类型", selection: $type) {
                    ForEach(AccountType.allCases) { Text($0.title).tag($0) }
                }
                if type.supportsCardLastFour {
                    Section {
                        TextField("选填", text: $cardLastFour)
                            .keyboardType(.numberPad)
                            .onChange(of: cardLastFour) { _, value in
                                let sanitized = AccountCardIdentityStore.sanitizedInput(value)
                                if sanitized != value { cardLastFour = sanitized }
                            }
                    } header: {
                        Text("银行卡后四位")
                    } footer: {
                        Text("用于快捷指令记账时快速识别账户。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                TextField("备注", text: $note, axis: .vertical)
                Stepper("排序：\(sortOrder)", value: $sortOrder, in: 0...999)
                Toggle("从资产列表隐藏", isOn: $isHidden)
            }
            .navigationTitle("编辑账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
        }
    }

    private func save() {
        do {
            try AccountService(context: context).update(
                account,
                name: name,
                type: type,
                note: note,
                sortOrder: sortOrder,
                isHidden: isHidden,
                cardLastFour: type.supportsCardLastFour ? cardLastFour : nil
            )
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct ArchivedAccountManagementView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.updatedAt, order: .reverse) private var accounts: [Account]
    @State private var errorMessage: String?

    var body: some View {
        List {
            let archived = accounts.filter(\.isArchived)
            if archived.isEmpty {
                ContentUnavailableView("没有归档账户", systemImage: "archivebox")
            } else {
                ForEach(archived) { account in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(account.name)
                            Text(account.book?.name ?? "未归属账本").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("恢复") { restore(account) }.buttonStyle(.bordered)
                    }
                }
            }
        }
        .navigationTitle("归档账户")
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("好") {} } message: { Text(errorMessage ?? "未知错误") }
    }

    private func restore(_ account: Account) {
        do { try AccountService(context: context).setArchived(false, account: account) }
        catch { errorMessage = error.localizedDescription }
    }
}

struct TransactionCompactRow: View {
    let transaction: LedgerTransaction

    var body: some View {
        HStack {
            Image(systemName: transaction.category?.symbolName ?? transaction.type.symbolName)
                .foregroundStyle(transaction.type.color)
                .frame(width: 28)
            VStack(alignment: .leading) {
                Text(transaction.category?.name ?? transaction.type.title)
                Text(transaction.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(transaction.summaryAmount)
                .monospacedDigit()
                .foregroundStyle(transaction.type.color)
        }
    }
}

extension TransactionKind {
    var symbolName: String {
        switch self {
        case .expense: "arrow.up.circle"
        case .income: "arrow.down.circle"
        case .transfer: "arrow.left.arrow.right.circle"
        case .exchange: "arrow.triangle.2.circlepath.circle"
        case .adjustment: "slider.horizontal.3"
        }
    }

    var color: Color {
        switch self {
        case .expense: .red
        case .income: .green
        case .transfer: .blue
        case .exchange: .orange
        case .adjustment: .purple
        }
    }
}

extension LedgerTransaction {
    var summaryAmount: String {
        switch type {
        case .expense:
            "−" + MoneyFormatter.string(sourceAmount ?? amount ?? 0, currencyCode: sourceCurrencyCode ?? currencyCode ?? "CNY")
        case .income:
            "+" + MoneyFormatter.string(sourceAmount ?? amount ?? 0, currencyCode: sourceCurrencyCode ?? currencyCode ?? "CNY")
        case .transfer:
            MoneyFormatter.string(sourceAmount ?? 0, currencyCode: sourceCurrencyCode ?? "CNY")
        case .exchange:
            "\(MoneyFormatter.plain(sourceAmount ?? 0, currencyCode: sourceCurrencyCode ?? "CNY")) \(sourceCurrencyCode ?? "") → \(MoneyFormatter.plain(destinationAmount ?? 0, currencyCode: destinationCurrencyCode ?? "CNY")) \(destinationCurrencyCode ?? "")"
        case .adjustment:
            (adjustmentDirection == .decrease ? "−" : "+") + MoneyFormatter.string(sourceAmount ?? amount ?? 0, currencyCode: sourceCurrencyCode ?? currencyCode ?? "CNY")
        }
    }
}
