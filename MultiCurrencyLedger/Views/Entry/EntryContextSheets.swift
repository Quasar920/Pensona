import SwiftUI

enum EntryDateTimePickerMode {
    case date
    case time
}

struct EntryAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let wallets: [CurrencyWallet]
    let selectedID: UUID?
    let allowsSkipping: Bool
    let select: (CurrencyWallet?) -> Void
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
            ScrollView {
                LazyVStack(spacing: 9) {
                    if allowsSkipping {
                        Button {
                            select(nil)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "circle")
                                    .font(.headline).foregroundStyle(.secondary)
                                    .frame(width: 36, height: 36)
                                    .background(Color.primary.opacity(0.06), in: Circle())
                                Text("暂时不记")
                                    .font(.headline)
                                Spacer()
                                if selectedID == nil {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(LedgerPalette.accent)
                                }
                            }
                            .padding(14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .ledgerSurface(.functional, cornerRadius: 20)
                    }
                    ForEach(filtered) { wallet in
                        Button {
                            select(wallet)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: wallet.account?.type.symbolName ?? "creditcard")
                                    .font(.headline).foregroundStyle(LedgerPalette.accent)
                                    .frame(width: 36, height: 36)
                                    .background(LedgerPalette.accent.opacity(0.10), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(wallet.account?.name ?? AppLocalization.string("未知账户"))
                                        .font(.headline)
                                    Text("\(wallet.currencyCode) · \(MoneyFormatter.plain(wallet.balance, currencyCode: wallet.currencyCode))")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedID == wallet.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(LedgerPalette.accent)
                                }
                            }
                            .padding(14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .ledgerSurface(.functional, cornerRadius: 20)
                    }
                }
                .padding(18)
            }
            .ledgerPageBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索账户或币种")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

struct EntryDateTimeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var date: Date
    @State private var draftDate: Date
    let mode: EntryDateTimePickerMode

    init(date: Binding<Date>, mode: EntryDateTimePickerMode) {
        _date = date
        _draftDate = State(initialValue: date.wrappedValue)
        self.mode = mode
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if mode == .date {
                    DatePicker("日期", selection: $draftDate, displayedComponents: [.date])
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .ledgerSurface(.sheetChrome, cornerRadius: 22)
                } else {
                    DatePicker("选择日期与时间", selection: $draftDate)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .padding(18)
                        .ledgerSurface(.sheetChrome, cornerRadius: 22)
                        .accessibilityIdentifier("entry-date-time-wheel")
                }
                Button("回到现在") { draftDate = .now }
                    .buttonStyle(.bordered)
                Spacer()
            }
            .padding(18)
            .ledgerPageBackground()
            .navigationTitle(mode == .date ? "选择日期" : "选择时间")
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

struct EntryDiscountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var state: TransactionFormState
    @FocusState private var isDiscountFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("优惠")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("0", text: $state.discountAmountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.title3.monospacedDigit())
                        .focused($isDiscountFocused)
                }
                .padding(16)
                .ledgerSurface(.functional, cornerRadius: 20)
                Text("填写本次优惠金额")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(18)
            .ledgerPageBackground()
            .navigationTitle("优惠信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { isDiscountFocused = true }
        }
    }
}

struct EntryCreditCardRepaymentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var state: TransactionFormState
    let sourceWallet: CurrencyWallet?
    let cardWallets: [CurrencyWallet]

    private var selectedWallet: CurrencyWallet? {
        cardWallets.first { $0.id == state.destinationWalletID }
    }

    private var isCrossCurrency: Bool {
        guard let sourceWallet, let selectedWallet else { return false }
        return sourceWallet.currencyCode != selectedWallet.currencyCode
    }

    private var outstanding: Decimal {
        max(0, -(selectedWallet?.balance ?? 0))
    }

    private var actualRate: Decimal? {
        guard isCrossCurrency,
              let baseAmount = DecimalParser.parse(state.amountText), baseAmount > 0,
              let foreignAmount = DecimalParser.parse(state.destinationAmountText), foreignAmount > 0 else {
            return nil
        }
        return EntryCalculationState.round(baseAmount / foreignAmount, scale: 8)
    }

    private var exceedsOutstanding: Bool {
        guard let amount = DecimalParser.parse(state.destinationAmountText) else { return false }
        return amount > outstanding
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("还款币种")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(cardWallets) { wallet in
                                Button {
                                    select(wallet)
                                } label: {
                                    VStack(spacing: 3) {
                                        Text(wallet.currencyCode)
                                            .font(.headline.monospaced())
                                        Text("欠款 \(MoneyFormatter.plain(max(0, -wallet.balance), currencyCode: wallet.currencyCode))")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 50)
                                    .background(
                                        state.destinationWalletID == wallet.id
                                            ? LedgerPalette.accent.opacity(0.14)
                                            : Color.primary.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                                            .stroke(
                                                state.destinationWalletID == wallet.id
                                                    ? LedgerPalette.accent.opacity(0.55)
                                                    : Color.primary.opacity(0.08),
                                                lineWidth: 0.8
                                            )
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)

                    if isCrossCurrency {
                        repaymentField(
                            title: "本位币还款",
                            currencyCode: sourceWallet?.currencyCode ?? "--",
                            text: $state.amountText
                        )
                        repaymentField(
                            title: "偿还外币",
                            currencyCode: selectedWallet?.currencyCode ?? "--",
                            text: $state.destinationAmountText
                        )

                        LabeledContent {
                            Text(actualRate.map(EntryCalculationState.string) ?? "--")
                                .font(.headline.monospacedDigit())
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("实际汇率")
                                Text("本位币金额 ÷ 外币金额")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        if exceedsOutstanding {
                            Label(
                                "偿还金额不能超过当前 \(selectedWallet?.currencyCode ?? "") 欠款",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LedgerPalette.ink)
                        }
                    } else {
                        Text("本次为同币种还款，转出金额将直接冲减信用卡欠款。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(18)
            }
            .ledgerPageBackground()
            .navigationTitle("信用卡还款")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        if let actualRate {
                            state.exchangeRateText = EntryCalculationState.string(actualRate)
                        }
                        dismiss()
                    }
                    .disabled(exceedsOutstanding)
                }
            }
            .onChange(of: state.amountText) { _, _ in updateRate() }
            .onChange(of: state.destinationAmountText) { _, _ in updateRate() }
            .onAppear(perform: updateRate)
        }
    }

    private func repaymentField(
        title: String,
        currencyCode: String,
        text: Binding<String>
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(currencyCode)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.title3.weight(.semibold).monospacedDigit())
        }
        .padding(14)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func select(_ wallet: CurrencyWallet) {
        let changedCurrency = selectedWallet?.currencyCode != wallet.currencyCode
        state.destinationWalletID = wallet.id
        if wallet.currencyCode == sourceWallet?.currencyCode {
            state.destinationAmountText = state.amountText
            state.exchangeRateText = ""
        } else if changedCurrency {
            state.destinationAmountText = ""
            state.exchangeRateText = ""
        }
    }

    private func updateRate() {
        guard let actualRate else {
            if isCrossCurrency { state.exchangeRateText = "" }
            return
        }
        state.exchangeRateText = EntryCalculationState.string(actualRate)
    }
}

struct EntryForeignInstallmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    let draft: TransactionDraft
    let outstanding: Decimal
    let confirm: (String, Int) -> Void
    let cancel: () -> Void

    @State private var name: String
    @State private var installmentCount = 3

    init(
        draft: TransactionDraft,
        outstanding: Decimal,
        confirm: @escaping (String, Int) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.draft = draft
        self.outstanding = outstanding
        self.confirm = confirm
        self.cancel = cancel
        let cardName = draft.destinationWallet?.account?.name ?? "信用卡"
        let code = draft.destinationWallet?.currencyCode ?? ""
        _name = State(initialValue: "\(cardName) \(code) 分期")
    }

    private var principalParts: [Decimal] {
        (try? InstallmentAllocator.allocations(
            total: outstanding,
            count: installmentCount,
            fractionDigits: SupportedCurrency.fractionDigits(
                for: draft.destinationWallet?.currencyCode ?? SupportedCurrency.CNY.rawValue
            )
        )) ?? []
    }

    private var firstPrincipal: Decimal {
        principalParts.first ?? 0
    }

    private var firstRate: Decimal? {
        guard draft.amount > 0, firstPrincipal > 0 else { return nil }
        return EntryCalculationState.round(draft.amount / firstPrincipal, scale: 8)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("计划名称")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("例如：美元账单分期", text: $name)
                            .textFieldStyle(.plain)
                            .font(.headline)
                    }
                    .padding(14)
                    .ledgerSurface(.functional, cornerRadius: 18)

                    VStack(spacing: 12) {
                        HStack {
                            Text("分期期数")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Stepper("\(installmentCount) 期", value: $installmentCount, in: 2...120)
                                .fixedSize()
                        }
                        Divider()
                        planRow(
                            "总外币本金",
                            MoneyFormatter.string(
                                outstanding,
                                currencyCode: draft.destinationWallet?.currencyCode ?? ""
                            )
                        )
                        planRow(
                            "第 1 期外币本金",
                            MoneyFormatter.string(
                                firstPrincipal,
                                currencyCode: draft.destinationWallet?.currencyCode ?? ""
                            )
                        )
                        planRow(
                            "第 1 期本位币还款",
                            MoneyFormatter.string(
                                draft.amount,
                                currencyCode: draft.sourceWallet?.currencyCode ?? ""
                            )
                        )
                        planRow(
                            "第 1 期实际汇率",
                            firstRate.map(EntryCalculationState.string) ?? "--"
                        )
                    }
                    .padding(14)
                    .ledgerSurface(.functional, cornerRadius: 18)

                    if let entered = draft.destinationAmount, entered != firstPrincipal {
                        Label(
                            "选择期数后，第 1 期外币本金调整为平均分配金额；本位币实际还款金额保持不变。",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("后续每一期都需要再次确认实际本位币还款金额，系统会分别记录当期汇率。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(18)
            }
            .ledgerPageBackground()
            .navigationTitle("创建外币分期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        let resolvedName = name
                        let resolvedCount = installmentCount
                        dismiss()
                        confirm(resolvedName, resolvedCount)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func planRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }
}

struct EntrySupplementarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var state: TransactionFormState
    let wallets: [CurrencyWallet]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
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
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.trailing)
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .ledgerSurface(.functional, cornerRadius: 20)
                    }
                    if state.kind == .transfer || state.kind == .exchange, state.includesFee {
                        fieldCard(title: "手续费扣款账户") {
                            Picker("账户", selection: $state.feeWalletID) {
                                ForEach(wallets) { wallet in
                                    Text(wallet.account?.name ?? wallet.currencyCode).tag(wallet.id as UUID?)
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
            .ledgerPageBackground()
            .navigationTitle("更多信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }

    private func fieldCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
        .padding(16)
        .ledgerSurface(.functional, cornerRadius: 20)
    }
}
