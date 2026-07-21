import SwiftData
import SwiftUI

struct InstallmentPlanManagementView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("selectedBookID") private var selectedBookID = ""
    @Query(sort: [SortDescriptor(\LedgerBook.sortOrder), SortDescriptor(\LedgerBook.createdAt)])
    private var books: [LedgerBook]
    @Query(sort: \Account.createdAt) private var accounts: [Account]
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @Query(sort: \InstallmentPlan.nextDueDate) private var plans: [InstallmentPlan]
    @Query private var occurrences: [InstallmentOccurrence]
    @State private var showingAdd = false
    @State private var errorMessage: String?
    @State private var resultMessage: String?

    private var selectedBook: LedgerBook? {
        books.first { $0.id.uuidString == selectedBookID } ?? books.first
    }

    private var wallets: [CurrencyWallet] {
        guard selectedBook != nil else { return [] }
        return accounts.filter { !$0.isArchived }.flatMap(\.enabledWallets)
    }

    private var scopedPlans: [InstallmentPlan] {
        guard let bookID = selectedBook?.id else { return [] }
        return plans.filter { $0.bookID == bookID && !$0.isArchived }
    }

    var body: some View {
        List {
            if scopedPlans.isEmpty {
                ContentUnavailableView {
                    Label("还没有分期计划", systemImage: "calendar.badge.clock")
                } description: {
                    Text("消费分期按期记录支出；账单分期按还款转账记录本金，手续费单独计入。")
                } actions: {
                    Button("新建分期") { showingAdd = true }
                }
            } else {
                ForEach(scopedPlans) { plan in planRow(plan) }
            }
            if let resultMessage {
                Section { Label(resultMessage, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        }
        .navigationTitle("分期管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Label("新建", systemImage: "plus") }
                    .disabled(selectedBook == nil || wallets.isEmpty)
            }
        }
        .sheet(isPresented: $showingAdd) {
            if let book = selectedBook {
                InstallmentPlanEditorView(
                    book: book,
                    wallets: wallets,
                    categories: categories.filter {
                        !$0.isArchived && $0.type == .expense
                    }
                )
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("好") {} } message: { Text(errorMessage ?? AppLocalization.string("未知错误")) }
    }

    @ViewBuilder
    private func planRow(_ plan: InstallmentPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.name).font(.headline)
                    Text("\(plan.kind.title) · \(plan.nextInstallmentIndex)/\(plan.installmentCount) 期")
                        .font(.caption).foregroundStyle(.secondary)
                    if !plan.isCompleted {
                        Text("下次 \(plan.nextDueDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if plan.isCompleted { Text("已结束").font(.caption).foregroundStyle(.green) }
                else if plan.isPaused { Text("已暂停").font(.caption).foregroundStyle(.orange) }
            }
            HStack {
                if !plan.isCompleted {
                    Button("补生成到今天") { generate(plan) }
                        .buttonStyle(.bordered).disabled(plan.isPaused)
                    Button(plan.isPaused ? AppLocalization.string("恢复") : AppLocalization.string("暂停")) {
                        togglePause(plan)
                    }
                        .buttonStyle(.bordered)
                    Menu {
                        Button("提前结束", role: .destructive) { finishEarly(plan) }
                        Button("归档", role: .destructive) { archive(plan) }
                    } label: { Image(systemName: "ellipsis.circle") }
                } else {
                    Text("已生成 \(occurrences.filter { $0.planID == plan.id }.count) 笔")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("归档", role: .destructive) { archive(plan) }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func generate(_ plan: InstallmentPlan) {
        do {
            let count = try InstallmentPlanService(context: context).generateDue(for: plan).count
            resultMessage = count == 0
                ? AppLocalization.string("当前没有到期分期")
                : AppLocalization.string("已生成 \(count) 期交易")
        } catch { errorMessage = error.localizedDescription }
    }

    private func togglePause(_ plan: InstallmentPlan) {
        do { try InstallmentPlanService(context: context).setPaused(!plan.isPaused, plan: plan) }
        catch { errorMessage = error.localizedDescription }
    }

    private func finishEarly(_ plan: InstallmentPlan) {
        do { try InstallmentPlanService(context: context).finishEarly(plan) }
        catch { errorMessage = error.localizedDescription }
    }

    private func archive(_ plan: InstallmentPlan) {
        do { try InstallmentPlanService(context: context).setArchived(true, plan: plan) }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct InstallmentPlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let book: LedgerBook
    let wallets: [CurrencyWallet]
    let categories: [LedgerCategory]
    @State private var name = ""
    @State private var kind: InstallmentKind = .consumption
    @State private var principalText = ""
    @State private var feeText = "0"
    @State private var count = 3
    @State private var startDate = Date.now
    @State private var sourceWalletID: UUID?
    @State private var destinationWalletID: UUID?
    @State private var categoryID: UUID?
    @State private var merchant = ""
    @State private var note = ""
    @State private var errorMessage: String?

    private var sourceWallet: CurrencyWallet? { wallets.first { $0.id == sourceWalletID } }
    private var billDestinations: [CurrencyWallet] {
        guard let sourceWallet else { return [] }
        return wallets.filter {
            $0.id != sourceWallet.id
                && $0.currencyCode == sourceWallet.currencyCode
                && ($0.account?.type == .creditCard || $0.account?.type == .payable)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("计划") {
                    TextField("名称", text: $name)
                    Picker("类型", selection: $kind) {
                        ForEach(InstallmentKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("总本金", text: $principalText).keyboardType(.decimalPad)
                    TextField("总手续费", text: $feeText).keyboardType(.decimalPad)
                    Stepper("期数：\(count)", value: $count, in: 2...120)
                    DatePicker("首期日期", selection: $startDate)
                }
                Section("账户") {
                    Picker(
                        kind == .bill ? AppLocalization.string("还款钱包") : AppLocalization.string("付款钱包"),
                        selection: $sourceWalletID
                    ) {
                        Text("请选择").tag(nil as UUID?)
                        ForEach(wallets) { Text(walletLabel($0)).tag($0.id as UUID?) }
                    }
                    if kind == .bill {
                        Picker("信用账户", selection: $destinationWalletID) {
                            Text("请选择").tag(nil as UUID?)
                            ForEach(billDestinations) { Text(walletLabel($0)).tag($0.id as UUID?) }
                        }
                        Text("本金按转账还款，不重复计入消费；手续费会计入现金流。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Picker("支出分类", selection: $categoryID) {
                            Text("未分类").tag(nil as UUID?)
                            ForEach(categories) { Text($0.name).tag($0.id as UUID?) }
                        }
                    }
                }
                Section("详情") {
                    TextField("商户或交易对象", text: $merchant)
                    TextField("备注", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("新建分期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .onAppear {
                sourceWalletID = sourceWalletID ?? wallets.first?.id
                categoryID = categoryID ?? categories.first?.id
                ensureDestination()
            }
            .onChange(of: kind) { _, _ in ensureDestination() }
            .onChange(of: sourceWalletID) { _, _ in ensureDestination() }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("好") {} } message: { Text(errorMessage ?? AppLocalization.string("未知错误")) }
        }
    }

    private func ensureDestination() {
        guard kind == .bill else { destinationWalletID = nil; return }
        if !billDestinations.contains(where: { $0.id == destinationWalletID }) {
            destinationWalletID = billDestinations.first?.id
        }
    }

    private func save() {
        do {
            guard let principal = DecimalParser.parse(principalText),
                  let fee = DecimalParser.parse(feeText),
                  let sourceWallet else {
                throw InstallmentPlanError.invalidPrincipal
            }
            try InstallmentPlanService(context: context).create(
                name: name,
                bookID: book.id,
                kind: kind,
                totalPrincipal: principal,
                totalFee: fee,
                installmentCount: count,
                startDate: startDate,
                sourceWallet: sourceWallet,
                destinationWallet: wallets.first { $0.id == destinationWalletID },
                category: categories.first { $0.id == categoryID },
                merchantOrCounterparty: merchant,
                note: note
            )
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func walletLabel(_ wallet: CurrencyWallet) -> String {
        "\(wallet.account?.name ?? AppLocalization.string("未命名")) · \(wallet.currencyCode)"
    }
}
