import SwiftUI
import UIKit

struct TransactionFormSections: View {
    @Binding var state: TransactionFormState
    let wallets: [CurrencyWallet]
    let categories: [LedgerCategory]
    @State private var showingAASplit = false

    private let adjustmentReasons = ["银行利息", "投资收益", "投资亏损", "手动校准", "其他"]

    private var sourceWallet: CurrencyWallet? {
        wallets.first { $0.id == state.sourceWalletID }
    }

    private var destinationWallet: CurrencyWallet? {
        wallets.first { $0.id == state.destinationWalletID }
    }

    private var feeWallet: CurrencyWallet? {
        wallets.first { $0.id == state.feeWalletID }
    }

    private var filteredCategories: [LedgerCategory] {
        let categoryKind: CategoryKind = state.kind == .income ? .income : .expense
        return categories.filter { $0.type == categoryKind }
    }

    private var destinationOptions: [CurrencyWallet] {
        guard let sourceWallet else { return [] }
        return wallets.filter { candidate in
            guard candidate.id != sourceWallet.id else { return false }
            switch state.kind {
            case .transfer:
                return candidate.currencyCode == sourceWallet.currencyCode
            case .exchange:
                return candidate.currencyCode != sourceWallet.currencyCode
            default:
                return false
            }
        }
    }

    var body: some View {
        Picker("类型", selection: $state.kind) {
            ForEach(TransactionKind.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)

        amountSection
        walletSection
        splitPaymentSection
        aaSplitSection
        detailSection
    }

    private var amountSection: some View {
        Section(state.kind == .exchange ? "换出金额" : "金额") {
            HStack(alignment: .firstTextBaseline) {
                Text(sourceWallet?.currencyCode ?? "--")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                TextField("0.00", text: $state.amountText)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            if state.kind == .exchange {
                HStack {
                    Text(destinationWallet?.currencyCode ?? "目标币种")
                        .foregroundStyle(.secondary)
                    TextField("换入金额", text: $state.destinationAmountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var walletSection: some View {
        Section("账户与币种") {
            Picker(state.kind == .transfer || state.kind == .exchange ? "从" : "钱包", selection: $state.sourceWalletID) {
                ForEach(wallets) { wallet in
                    Text(walletLabel(wallet)).tag(wallet.id as UUID?)
                }
            }

            if state.kind == .transfer || state.kind == .exchange {
                Picker("到", selection: $state.destinationWalletID) {
                    ForEach(destinationOptions) { wallet in
                        Text(walletLabel(wallet)).tag(wallet.id as UUID?)
                    }
                }

                Toggle("包含手续费", isOn: $state.includesFee)
                if state.includesFee {
                    Picker("手续费钱包", selection: $state.feeWalletID) {
                        ForEach(wallets) { wallet in
                            Text(walletLabel(wallet)).tag(wallet.id as UUID?)
                        }
                    }
                    HStack {
                        Text(feeWallet?.currencyCode ?? "--")
                            .foregroundStyle(.secondary)
                        TextField("手续费", text: $state.feeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Text("手续费会从所选钱包单独扣除。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var splitPaymentSection: some View {
        if state.kind == .expense || state.kind == .income {
            Section(state.kind == .expense ? "付款方式" : "收款方式") {
                Toggle(
                    state.kind == .expense ? "组合付款" : "多账户收款",
                    isOn: Binding(
                        get: { state.usesSplitPayment },
                        set: { state.setSplitPaymentEnabled($0, wallets: wallets) }
                    )
                )
                if state.usesSplitPayment {
                    ForEach(Array(state.paymentParts.indices), id: \.self) { index in
                        HStack {
                            if index == 0 {
                                Text(wallets.first { $0.id == state.sourceWalletID }.map(walletLabel) ?? "来源钱包")
                                    .font(.subheadline)
                                    .lineLimit(1)
                            } else {
                                Picker("钱包 \(index + 1)", selection: $state.paymentParts[index].walletID) {
                                    Text("请选择").tag(nil as UUID?)
                                    ForEach(splitWalletOptions) { wallet in
                                        Text(walletLabel(wallet)).tag(wallet.id as UUID?)
                                    }
                                }
                                .labelsHidden()
                            }
                            TextField("金额", text: $state.paymentParts[index].amountText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 110)
                            if index > 1 {
                                Button(role: .destructive) {
                                    state.paymentParts.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button {
                        state.paymentParts.append(PaymentPartFormState(walletID: splitWalletOptions.first?.id))
                    } label: {
                        Label("添加付款钱包", systemImage: "plus.circle")
                    }
                    Text("各分项必须使用相同币种，合计严格等于交易总额。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var splitWalletOptions: [CurrencyWallet] {
        guard let sourceWallet else { return [] }
        return wallets.filter { $0.currencyCode == sourceWallet.currencyCode }
    }

    @ViewBuilder
    private var aaSplitSection: some View {
        if state.kind == .expense {
            Section("AA 分摊") {
                Button {
                    showingAASplit = true
                } label: {
                    HStack {
                        Label(
                            state.aaSplitDraft == nil ? "设置 AA 分摊" : "编辑 AA 分摊",
                            systemImage: "person.2.fill"
                        )
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .disabled(aaTotalAmount <= 0)

                if let draft = state.aaSplitDraft,
                   let amounts = try? AASplitCalculator().amounts(
                    totalAmount: aaTotalAmount,
                    otherPeopleCount: draft.otherPeopleCount,
                    mode: draft.calculationMode,
                    customOthersOwedAmount: draft.othersOwedAmount,
                    currencyCode: aaCurrencyCode
                   ) {
                    Text("我和其他 \(draft.otherPeopleCount) 人 · 我的承担 \(MoneyFormatter.string(amounts.myShareAmount, currencyCode: aaCurrencyCode))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("移除 AA", role: .destructive) {
                        state.aaSplitDraft = nil
                    }
                } else if aaTotalAmount <= 0 {
                    Text("请先输入支出金额。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showingAASplit) {
                AASplitEditorView(
                    totalAmount: aaTotalAmount,
                    currencyCode: aaCurrencyCode,
                    initialDraft: state.aaSplitDraft
                ) { draft in
                    state.aaSplitDraft = draft
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var aaTotalAmount: Decimal {
        DecimalParser.parse(state.amountText) ?? 0
    }

    private var aaCurrencyCode: String {
        sourceWallet?.currencyCode ?? SupportedCurrency.CNY.rawValue
    }

    @ViewBuilder
    private var detailSection: some View {
        Section("详情") {
            if state.kind == .expense || state.kind == .income {
                Picker("分类", selection: $state.categoryID) {
                    Text("未分类").tag(nil as UUID?)
                    ForEach(filteredCategories) { category in
                        Label(category.name, systemImage: category.symbolName)
                            .tag(category.id as UUID?)
                    }
                }
                TextField("商户或交易对方（可选）", text: $state.merchantOrCounterparty)
            } else if state.kind == .transfer || state.kind == .exchange {
                TextField("交易对方（可选）", text: $state.merchantOrCounterparty)
            }

            if state.kind == .adjustment {
                Picker("方向", selection: $state.adjustmentDirection) {
                    ForEach(AdjustmentDirection.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("原因", selection: $state.adjustmentReason) {
                    ForEach(adjustmentReasons, id: \.self) { Text($0).tag($0) }
                }
            }

            DatePicker("日期", selection: $state.date)
            TextField("备注（可选）", text: $state.note, axis: .vertical)
        }
    }

    private func walletLabel(_ wallet: CurrencyWallet) -> String {
        let balance = MoneyFormatter.plain(wallet.balance, currencyCode: wallet.currencyCode)
        return "\(wallet.account?.name ?? "未知账户") / \(wallet.currencyCode) / \(balance)"
    }
}

// MARK: - Fast entry composer

struct EntryComposerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var state: TransactionFormState
    let wallets: [CurrencyWallet]
    let categories: [LedgerCategory]
    let successMessage: String?
    let showsNextEntry: Bool
    let isSaving: Bool
    let nextEntry: () -> Void
    let complete: () -> Void

    @State private var expandedMainID: UUID?
    @State private var showingSourceWallets = false
    @State private var showingDestinationWallets = false
    @State private var showingDatePicker = false
    @State private var showingMore = false
    @State private var activeAmount: EntryAmountTarget = .source
    @State private var keypadResetID = UUID()

    private var sourceWallet: CurrencyWallet? { wallets.first { $0.id == state.sourceWalletID } }
    private var destinationWallet: CurrencyWallet? { wallets.first { $0.id == state.destinationWalletID } }

    private var categoryKind: CategoryKind { state.kind == .income ? .income : .expense }
    private var relevantCategories: [LedgerCategory] {
        categories.filter { $0.type == categoryKind && !$0.isArchived }
    }
    private var mainCategories: [LedgerCategory] {
        let roots = relevantCategories.filter { $0.parentID == nil }
        return (roots.isEmpty ? relevantCategories : roots).sorted { $0.sortOrder < $1.sortOrder }
    }
    private var selectedCategory: LedgerCategory? {
        relevantCategories.first { $0.id == state.categoryID }
    }
    private var selectedMainID: UUID? {
        selectedCategory?.parentID ?? selectedCategory?.id
    }
    private var expandedChildren: [LedgerCategory] {
        guard let expandedMainID else { return [] }
        return relevantCategories
            .filter { $0.parentID == expandedMainID }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    private var destinationOptions: [CurrencyWallet] {
        guard let sourceWallet else { return [] }
        return wallets.filter {
            guard $0.id != sourceWallet.id else { return false }
            return state.kind == .transfer
                ? $0.currencyCode == sourceWallet.currencyCode
                : $0.currencyCode != sourceWallet.currencyCode
        }
    }
    private var amountBinding: Binding<String> {
        Binding(
            get: { activeAmount == .destination ? state.destinationAmountText : state.amountText },
            set: {
                if activeAmount == .destination { state.destinationAmountText = $0 }
                else { state.amountText = $0 }
            }
        )
    }
    // 品牌蓝是唯一主交互色；支出红仅保留给校验、风险和破坏性动作（交接文档 §5.2/§11.6）
    private var tint: Color { HomePalette.accent }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                kindPicker
                if state.kind == .expense || state.kind == .income {
                    categoryPicker
                } else if state.kind == .transfer || state.kind == .exchange {
                    movementCard
                }
                amountCard
                contextBar
                if let successMessage {
                    Label(successMessage, systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 8) {
            VStack(spacing: 10) {
                EntryAmountKeypad(amountText: amountBinding, tint: tint, resetID: keypadResetID)
                HStack(spacing: 10) {
                    if showsNextEntry {
                        Button("下一笔", action: nextEntry)
                            .buttonStyle(EntrySecondaryActionStyle())
                            .disabled(isSaving)
                    }
                    Button("完成", action: complete)
                        .buttonStyle(EntryPrimaryActionStyle(tint: tint))
                        .disabled(isSaving)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color(uiColor: .systemBackground).opacity(0.94))
            .overlay(alignment: .top) { Divider().opacity(0.35) }
        }
        .sheet(isPresented: $showingSourceWallets) {
            EntryWalletPicker(
                title: state.kind == .transfer || state.kind == .exchange ? "选择转出账户" : "选择账户",
                wallets: wallets,
                selectedID: state.sourceWalletID
            ) { state.sourceWalletID = $0.id }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingDestinationWallets) {
            EntryWalletPicker(title: "选择转入账户", wallets: destinationOptions, selectedID: state.destinationWalletID) {
                state.destinationWalletID = $0.id
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingDatePicker) {
            EntryDatePicker(date: $state.date)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingMore) {
            EntryMoreInformationView(state: $state, wallets: wallets)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            if let selectedMainID,
               relevantCategories.contains(where: { $0.parentID == selectedMainID }) {
                expandedMainID = selectedMainID
            }
        }
        .onChange(of: state.kind) { _, newKind in
            activeAmount = .source
            expandedMainID = nil
            keypadResetID = UUID()
            if newKind == .expense || newKind == .income,
               let first = mainCategories.first,
               !relevantCategories.contains(where: { $0.id == state.categoryID }) {
                state.categoryID = first.id
            }
        }
    }

    private var kindPicker: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(TransactionKind.allCases) { kind in
                        Button {
                            state.kind = kind
                        } label: {
                            Text(kind.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(state.kind == kind ? tint : .secondary)
                                .padding(.horizontal, 16)
                                .frame(height: 44)
                                .background(state.kind == kind ? tint.opacity(0.10) : Color.clear, in: Capsule())
                                .overlay(Capsule().stroke(state.kind == kind ? tint.opacity(0.64) : .clear))
                        }
                        .buttonStyle(LedgerGlassPressStyle())
                        .glassEffect(.regular.interactive(), in: Capsule())
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("分类").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let selectedCategory {
                    Text(categoryPath(selectedCategory)).font(.caption).foregroundStyle(tint)
                }
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(mainCategories) { category in
                        let isSelected = selectedMainID == category.id
                        Button { selectMain(category) } label: {
                            VStack(spacing: 7) {
                                Image(systemName: category.symbolName)
                                    .font(.system(size: 21, weight: .semibold))
                                Text(category.name).font(.caption.weight(.semibold)).lineLimit(1)
                            }
                            .foregroundStyle(isSelected ? tint : .primary)
                            .frame(width: 76, height: 66)
                            .background {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(isSelected ? tint.opacity(0.10) : Color.primary.opacity(0.045))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(
                                        isSelected ? tint.opacity(0.72) : Color.primary.opacity(0.08),
                                        lineWidth: isSelected ? 1.4 : 0.75
                                    )
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(LedgerGlassPressStyle())
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 5)
            }
            .scrollIndicators(.hidden)

            if !expandedChildren.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(Array(expandedChildren.enumerated()), id: \.element.id) { index, child in
                            let isSelected = state.categoryID == child.id
                            Button {
                                state.categoryID = child.id
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: child.symbolName).font(.caption.weight(.semibold))
                                    Text(child.name).font(.caption.weight(.semibold)).lineLimit(1)
                                }
                                .foregroundStyle(isSelected ? tint : .primary)
                                .padding(.horizontal, 12)
                                .frame(height: 44)
                                .background {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(isSelected ? tint.opacity(0.10) : Color.primary.opacity(0.045))
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(
                                            isSelected ? tint.opacity(0.72) : Color.primary.opacity(0.08),
                                            lineWidth: isSelected ? 1.2 : 0.75
                                        )
                                }
                                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(LedgerGlassPressStyle())
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .offset(x: CGFloat(index - expandedChildren.count / 2) * -8, y: -12)
                                        .combined(with: .scale(scale: 0.78, anchor: .top))
                                        .combined(with: .opacity)
                            )
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 5)
                }
                .scrollIndicators(.hidden)
            }
        }
        .animation(reduceMotion ? LedgerMotion.reduced : LedgerMotion.responsive, value: expandedMainID)
    }

    private var movementCard: some View {
        HStack(spacing: 10) {
            movementWalletButton(title: "从", wallet: sourceWallet) { showingSourceWallets = true }
            Image(systemName: state.kind == .exchange ? "arrow.left.arrow.right" : "arrow.right")
                .font(.headline).foregroundStyle(tint)
            movementWalletButton(title: "到", wallet: destinationWallet) { showingDestinationWallets = true }
        }
        .padding(12)
        .ledgerGlassCard(cornerRadius: 22, tint: tint)
    }

    private func movementWalletButton(title: String, wallet: CurrencyWallet?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(wallet?.account?.name ?? "请选择").font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(wallet?.currencyCode ?? "--").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(LedgerGlassPressStyle())
    }

    private var amountCard: some View {
        VStack(spacing: 7) {
            if let selectedCategory, state.kind == .expense || state.kind == .income {
                Text(categoryPath(selectedCategory))
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            Button { selectAmountTarget(.source) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(sourceWallet?.currencyCode ?? "--")
                        .font(.headline.monospaced()).foregroundStyle(.secondary)
                    Text(state.amountText.isEmpty ? "0" : state.amountText)
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
                        .foregroundStyle(activeAmount == .source ? .primary : .secondary)
                }
            }
            .buttonStyle(.plain)
            if state.kind == .exchange {
                Button { selectAmountTarget(.destination) } label: {
                    HStack(spacing: 7) {
                        Text("换入").foregroundStyle(.secondary)
                        Text(destinationWallet?.currencyCode ?? "--").font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(state.destinationAmountText.isEmpty ? "0" : state.destinationAmountText)
                            .font(.title3.weight(.semibold).monospacedDigit())
                    }
                    .padding(.horizontal, 12).frame(height: 44)
                    .background(activeAmount == .destination ? tint.opacity(0.10) : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .ledgerGlassCard(cornerRadius: 26, tint: tint)
    }

    private var contextBar: some View {
        HStack(spacing: 8) {
            contextButton(
                title: sourceWallet?.account?.name ?? "账户",
                symbol: "creditcard",
                action: { showingSourceWallets = true }
            )
            contextButton(
                title: state.date.formatted(.dateTime.month().day()),
                symbol: "calendar",
                action: { showingDatePicker = true }
            )
            contextButton(title: "更多", symbol: "ellipsis", action: { showingMore = true })
        }
    }

    private func contextButton(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.subheadline.weight(.semibold))
                Text(title).font(.caption2.weight(.medium)).lineLimit(1)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(LedgerGlassPressStyle())
        .ledgerGlassCard(cornerRadius: 17, tint: tint)
    }

    private func selectMain(_ category: LedgerCategory) {
        state.categoryID = category.id
        let hasChildren = relevantCategories.contains { $0.parentID == category.id }
        withAnimation(reduceMotion ? LedgerMotion.reduced : LedgerMotion.responsive) {
            expandedMainID = hasChildren && expandedMainID != category.id ? category.id : nil
        }
    }

    private func categoryPath(_ category: LedgerCategory) -> String {
        guard let parentID = category.parentID,
              let parent = relevantCategories.first(where: { $0.id == parentID }) else { return category.name }
        return "\(parent.name) / \(category.name)"
    }

    private func selectAmountTarget(_ target: EntryAmountTarget) {
        activeAmount = target
        keypadResetID = UUID()
    }
}

private enum EntryAmountTarget { case source, destination }

private struct EntryAmountKeypad: View {
    @Binding var amountText: String
    let tint: Color
    let resetID: UUID
    @State private var leftValue: Decimal?
    @State private var pendingOperation: Character?
    @State private var operandText = ""

    private let rows = [
        ["1", "2", "3", "+"],
        ["4", "5", "6", "−"],
        ["7", "8", "9", "⌫"],
        ["C", "0", ".", "00"]
    ]

    var body: some View {
        VStack(spacing: 7) {
            if let pendingOperation {
                Text("\(NSDecimalNumber(decimal: leftValue ?? .zero).stringValue) \(String(pendingOperation)) \(operandText)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 6)
            }
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button { press(key) } label: {
                            Group {
                                if key == "⌫" { Image(systemName: "delete.left") }
                                else { Text(key) }
                            }
                            .font(.system(size: key == "C" ? 16 : 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(key == "+" || key == "−" ? tint : .primary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(LedgerGlassPressStyle())
                    }
                }
            }
        }
        .padding(10)
        .ledgerGlassCard(cornerRadius: 22, tint: tint)
        .onChange(of: resetID) { _, _ in resetCalculation() }
        .onChange(of: amountText) { _, newValue in
            if newValue.isEmpty { resetCalculation() }
        }
    }

    private func press(_ key: String) {
        switch key {
        case "+", "−": beginOperation(key == "+" ? "+" : "-")
        case "⌫": deleteDigit()
        case "C": amountText = ""; resetCalculation()
        default: append(key)
        }
    }

    private func append(_ value: String) {
        if pendingOperation != nil {
            operandText = append(value, to: operandText)
            recalculate()
        } else {
            amountText = append(value, to: amountText)
        }
    }

    private func append(_ value: String, to current: String) -> String {
        if value == "." {
            guard !current.contains(".") else { return current }
            return current.isEmpty ? "0." : current + "."
        }
        if current == "0" && value != "00" { return value }
        let candidate = current + value
        let parts = candidate.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.first?.count ?? 0 <= 12, parts.count < 2 || parts[1].count <= 3 else { return current }
        return candidate
    }

    private func beginOperation(_ operation: Character) {
        guard let current = DecimalParser.parse(amountText) else { return }
        leftValue = current
        pendingOperation = operation
        operandText = ""
    }

    private func recalculate() {
        guard let leftValue, let pendingOperation,
              let right = DecimalParser.parse(operandText) else { return }
        let result = pendingOperation == "+" ? leftValue + right : leftValue - right
        amountText = NSDecimalNumber(decimal: max(result, .zero)).stringValue
    }

    private func deleteDigit() {
        if pendingOperation != nil {
            guard !operandText.isEmpty else { resetCalculation(); return }
            operandText.removeLast()
            if operandText.isEmpty { amountText = NSDecimalNumber(decimal: leftValue ?? .zero).stringValue }
            else { recalculate() }
        } else if !amountText.isEmpty {
            amountText.removeLast()
        }
    }

    private func resetCalculation() {
        leftValue = nil
        pendingOperation = nil
        operandText = ""
    }
}

private struct EntryWalletPicker: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let wallets: [CurrencyWallet]
    let selectedID: UUID?
    let select: (CurrencyWallet) -> Void
    @State private var searchText = ""

    private var filtered: [CurrencyWallet] {
        guard !searchText.isEmpty else { return wallets }
        return wallets.filter {
            ($0.account?.name ?? "").localizedCaseInsensitiveContains(searchText)
                || $0.currencyCode.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomePalette.background.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { wallet in
                            Button {
                                select(wallet)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: wallet.account?.type.symbolName ?? "creditcard")
                                        .font(.headline).foregroundStyle(HomePalette.accent)
                                        .frame(width: 36, height: 36)
                                        .background(HomePalette.accent.opacity(0.10), in: Circle())
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(wallet.account?.name ?? "未知账户").font(.headline)
                                        Text("\(wallet.currencyCode) · \(MoneyFormatter.plain(wallet.balance, currencyCode: wallet.currencyCode))")
                                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedID == wallet.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(HomePalette.accent) }
                                }
                                .padding(14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .ledgerGlassCard(cornerRadius: 20)
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索账户或币种")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

private struct EntryDatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var date: Date
    @State private var draftDate: Date

    init(date: Binding<Date>) {
        _date = date
        _draftDate = State(initialValue: date.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                DatePicker("日期与时间", selection: $draftDate)
                    .datePickerStyle(.graphical)
                    .padding(14)
                    .ledgerGlassCard(cornerRadius: 24)
                Button("回到现在") { draftDate = .now }
                    .buttonStyle(.bordered)
                Spacer()
            }
            .padding(18)
            .background(HomePalette.background.ignoresSafeArea())
            .navigationTitle("选择日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { date = draftDate; dismiss() }
                }
            }
        }
    }
}

private struct EntryMoreInformationView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var state: TransactionFormState
    let wallets: [CurrencyWallet]
    private let adjustmentReasons = ["银行利息", "投资收益", "投资亏损", "手动校准", "其他"]
    @State private var showingAASplit = false

    private var aaTotalAmount: Decimal {
        DecimalParser.parse(state.amountText) ?? 0
    }

    private var aaCurrencyCode: String {
        wallets.first { $0.id == state.sourceWalletID }?.currencyCode
            ?? SupportedCurrency.CNY.rawValue
    }

    private var aaSummary: String? {
        guard let draft = state.aaSplitDraft,
              let amounts = try? AASplitCalculator().amounts(
                totalAmount: aaTotalAmount,
                otherPeopleCount: draft.otherPeopleCount,
                mode: draft.calculationMode,
                customOthersOwedAmount: draft.othersOwedAmount,
                currencyCode: aaCurrencyCode
              ) else { return nil }
        return "我和其他 \(draft.otherPeopleCount) 人 · 我的承担 \(MoneyFormatter.string(amounts.myShareAmount, currencyCode: aaCurrencyCode))"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HomePalette.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        if state.kind == .expense || state.kind == .income || state.kind == .transfer || state.kind == .exchange {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(state.kind == .expense || state.kind == .income ? "商户或交易对方" : "交易对方")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                TextField("可选", text: $state.merchantOrCounterparty)
                                    .textFieldStyle(.plain)
                            }
                            .padding(16).ledgerGlassCard(cornerRadius: 20)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("备注").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            TextField("添加自己的说明", text: $state.note, axis: .vertical)
                                .lineLimit(2...5).textFieldStyle(.plain)
                        }
                        .padding(16).ledgerGlassCard(cornerRadius: 20)

                        if state.kind == .expense {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    Button {
                                        showingAASplit = true
                                    } label: {
                                        HStack {
                                            Label(
                                                state.aaSplitDraft == nil ? "AA 分摊" : "编辑 AA 分摊",
                                                systemImage: "person.2.fill"
                                            )
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.tertiary)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(aaTotalAmount <= 0)

                                    if state.aaSplitDraft != nil {
                                        Button(role: .destructive) {
                                            state.aaSplitDraft = nil
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .frame(width: 36, height: 36)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("移除 AA 分摊")
                                    }
                                }
                                if let aaSummary {
                                    Text(aaSummary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if aaTotalAmount <= 0 {
                                    Text("请先输入支出金额，再设置 AA。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(16).ledgerGlassCard(cornerRadius: 20)
                        }

                        if state.kind == .adjustment {
                            VStack(spacing: 12) {
                                Picker("方向", selection: $state.adjustmentDirection) {
                                    ForEach(AdjustmentDirection.allCases) { Text($0.title).tag($0) }
                                }.pickerStyle(.segmented)
                                Picker("调整原因", selection: $state.adjustmentReason) {
                                    ForEach(adjustmentReasons, id: \.self) { Text($0).tag($0) }
                                }
                            }
                            .padding(16).ledgerGlassCard(cornerRadius: 20)
                        }

                        if state.kind == .expense || state.kind == .income {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle(state.kind == .expense ? "组合付款" : "多账户收款", isOn: Binding(
                                    get: { state.usesSplitPayment },
                                    set: { state.setSplitPaymentEnabled($0, wallets: wallets) }
                                ))
                                if state.usesSplitPayment {
                                    ForEach(Array(state.paymentParts.indices), id: \.self) { index in
                                        HStack {
                                            Picker("账户", selection: $state.paymentParts[index].walletID) {
                                                ForEach(wallets) { wallet in
                                                    Text(wallet.account?.name ?? wallet.currencyCode).tag(wallet.id as UUID?)
                                                }
                                            }
                                            TextField("金额", text: $state.paymentParts[index].amountText)
                                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                        }
                                    }
                                }
                            }
                            .padding(16).ledgerGlassCard(cornerRadius: 20)
                        }

                        if state.kind == .transfer || state.kind == .exchange {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("包含手续费", isOn: $state.includesFee)
                                if state.includesFee {
                                    TextField("手续费金额", text: $state.feeText).keyboardType(.decimalPad)
                                    Picker("扣款账户", selection: $state.feeWalletID) {
                                        ForEach(wallets) { wallet in
                                            Text(wallet.account?.name ?? wallet.currencyCode).tag(wallet.id as UUID?)
                                        }
                                    }
                                }
                            }
                            .padding(16).ledgerGlassCard(cornerRadius: 20)
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("更多信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $showingAASplit) {
                AASplitEditorView(
                    totalAmount: aaTotalAmount,
                    currencyCode: aaCurrencyCode,
                    initialDraft: state.aaSplitDraft
                ) { draft in
                    state.aaSplitDraft = draft
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

private struct EntryPrimaryActionStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .glassEffect(.regular.tint(tint).interactive(), in: Capsule())
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(
                LedgerMotion.press(isPressed: configuration.isPressed),
                value: configuration.isPressed
            )
    }
}

private struct EntrySecondaryActionStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .glassEffect(.regular.interactive(), in: Capsule())
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(
                LedgerMotion.press(isPressed: configuration.isPressed),
                value: configuration.isPressed
            )
    }
}
