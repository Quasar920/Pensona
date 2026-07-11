import SwiftData
import SwiftUI

struct AccountDetailView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerTransaction.date, order: .reverse) private var transactions: [LedgerTransaction]
    let account: Account
    @State private var showingAddWallet = false

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
            }

            Section {
                if account.enabledWallets.isEmpty {
                    Text("尚未添加币种").foregroundStyle(.secondary)
                } else {
                    ForEach(account.enabledWallets) { wallet in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(wallet.currencyCode).font(.headline)
                                Text(wallet.currency?.localizedName ?? wallet.currencyCode)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(MoneyFormatter.string(wallet.balance, currencyCode: wallet.currencyCode))
                                .monospacedDigit()
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
        .sheet(isPresented: $showingAddWallet) {
            AddWalletView(account: account)
        }
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
