import SwiftUI

struct EntryContextOverlayPanel: View {
    @Environment(\.colorScheme) private var colorScheme

    let kind: EntryContextOverlayKind
    @Binding var draft: EntryContextDraft
    @Binding var activePaymentPart: Int
    let mainAmountText: String
    let wallets: [CurrencyWallet]
    let currencyCode: String
    let maximumHeight: CGFloat
    let isAAPeopleInputActive: Bool
    let cancel: () -> Void
    let commit: () -> Void
    let paymentPartChanged: () -> Void
    let aaPeopleInputSelected: () -> Void

    @AccessibilityFocusState private var titleFocused: Bool

    private var title: String {
        switch kind {
        case .account: "选择账户"
        case .aa: "AA 分摊"
        case .splitPayment: "组合支付"
        case .discount: "优惠"
        case .fee: "手续费"
        case .foreignExpense: "信用卡外币消费"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                    .accessibilityFocused($titleFocused)
                Spacer()
                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.07), in: Circle())
                }
                .buttonStyle(LedgerGlassPressStyle())
                .accessibilityLabel("取消")
            }

            content
        }
        .padding(16)
        .background(panelSurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.55), lineWidth: 0.8)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: EntryContextPanelFramePreferenceKey.self,
                    value: proxy.frame(in: .named(EntryContextCoordinateSpace.name))
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear {
            Task { @MainActor in
                titleFocused = true
            }
        }
    }

    private var panelSurface: Color {
        colorScheme == .dark
            ? Color(white: 0.10).opacity(0.94)
            : Color.white.opacity(0.84)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .account:
            accountOptions
        case .aa:
            aaOptions
        case .splitPayment:
            splitPaymentOptions
        case .discount:
            discountOptions
        case .fee, .foreignExpense:
            EmptyView()
        }
    }

    private var accountOptions: some View {
        ScrollView {
            VStack(spacing: 8) {
                accountRow(name: "暂时不记", wallet: nil)
                ForEach(wallets) { wallet in
                    accountRow(name: wallet.account?.name ?? wallet.currencyCode, wallet: wallet)
                }
            }
        }
        .frame(height: accountContentHeight)
        .scrollIndicators(.hidden)
    }

    private var accountContentHeight: CGFloat {
        min(
            max(120, CGFloat(wallets.count + 1) * 56),
            max(120, maximumHeight - 74)
        )
    }

    private func accountRow(name: String, wallet: CurrencyWallet?) -> some View {
        Button {
            draft.selectedWalletID = wallet?.id
            commit()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: wallet?.account?.type.symbolName ?? "circle")
                    .foregroundStyle(LedgerPalette.accent)
                    .frame(width: 28)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if draft.selectedWalletID == wallet?.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(LedgerPalette.accent)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(LedgerGlassPressStyle())
    }

    private var aaOptions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("总人数（含自己）")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Button(action: aaPeopleInputSelected) {
                    Text(aaPeopleDisplayText)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(
                            draft.hasValidAAPeople ? Color.primary : Color.red
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(minWidth: 52, minHeight: 44)
                        .background(
                            Color.primary.opacity(
                                isAAPeopleInputActive ? 0.075 : 0.055
                            ),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        draft.hasValidAAPeople
                                        ? Color.primary.opacity(
                                            isAAPeopleInputActive ? 0.18 : 0.10
                                        )
                                        : Color.red.opacity(0.7),
                                        lineWidth: 1
                                    )
                        }
                }
                .buttonStyle(LedgerGlassPressStyle())
                .accessibilityLabel("输入总人数")
                .accessibilityValue(aaPeopleDisplayText)
                .accessibilityHint("人数必须为不小于 2 的整数")

                HStack(spacing: 0) {
                    aaPeopleStepButton(systemName: "minus", delta: -1)
                    Divider()
                        .frame(height: 22)
                    aaPeopleStepButton(systemName: "plus", delta: 1)
                }
                .frame(height: 44)
                .background(Color.primary.opacity(0.09), in: Capsule())
            }
            .padding(14)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack {
                Text("其他人合计应还")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(MoneyFormatter.string(aaOwedAmount, currencyCode: currencyCode))
                    .font(.headline.monospacedDigit())
            }

            Button(action: commit) {
                Text("完成")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(LedgerGlassPressStyle())
            .background(
                LedgerPalette.accent.opacity(0.16),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(LedgerPalette.accent.opacity(0.38), lineWidth: 0.8)
            }
            .disabled(!draft.hasValidAAPeople)
        }
    }

    private var aaPeopleDisplayText: String {
        draft.aaPeopleText.isEmpty ? "— 人" : "\(draft.aaPeopleText) 人"
    }

    private func aaPeopleStepButton(systemName: String, delta: Int) -> some View {
        Button {
            let typedValue = Int(draft.aaPeopleText) ?? draft.aaPeople
            if delta < 0 {
                draft.setAAPeople(max(2, typedValue - 1))
            } else if typedValue < Int.max {
                draft.setAAPeople(max(2, typedValue + 1))
            }
        } label: {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(LedgerGlassPressStyle())
        .disabled(delta < 0 && (Int(draft.aaPeopleText) ?? draft.aaPeople) <= 2)
        .accessibilityLabel(delta < 0 ? "减少人数" : "增加人数")
    }

    private var aaOwedAmount: Decimal {
        let total = DecimalParser.parse(mainAmountText) ?? 0
        return total * Decimal(draft.aaPeople - 1) / Decimal(draft.aaPeople)
    }

    private var splitPaymentOptions: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(Array(draft.paymentParts.indices), id: \.self) { index in
                    HStack(spacing: 10) {
                        Menu {
                            ForEach(wallets) { wallet in
                                Button(wallet.account?.name ?? wallet.currencyCode) {
                                    draft.paymentParts[index].walletID = wallet.id
                                }
                            }
                        } label: {
                            Text(walletName(for: draft.paymentParts[index].walletID))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            activePaymentPart = index
                            paymentPartChanged()
                        } label: {
                            Text(
                                draft.paymentParts[index].amountText.isEmpty
                                    ? "输入金额"
                                    : draft.paymentParts[index].amountText
                            )
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(activePaymentPart == index ? LedgerPalette.accent : .primary)
                            .frame(width: 92, alignment: .trailing)
                        }
                    }
                    .padding(10)
                    .background(
                        activePaymentPart == index
                            ? LedgerPalette.accent.opacity(0.08)
                            : Color.primary.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }

                Button {
                    draft.paymentParts.append(PaymentPartFormState(walletID: nil))
                } label: {
                    Label("添加账户", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(height: splitPaymentContentHeight)
        .scrollIndicators(.hidden)
    }

    private var splitPaymentContentHeight: CGFloat {
        min(
            max(120, CGFloat(draft.paymentParts.count) * 58 + 44),
            max(120, maximumHeight - 74)
        )
    }

    private var discountOptions: some View {
        HStack {
            Text("优惠金额")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(draft.discountAmountText.isEmpty ? "0" : draft.discountAmountText)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(LedgerPalette.accent)
        }
        .padding(14)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func walletName(for id: UUID?) -> String {
        wallets.first(where: { $0.id == id })?.account?.name ?? "选择账户"
    }
}

/// A render-only counterpart for the Metal transition.
///
/// Native controls and system materials cannot be captured reliably inside a
/// SwiftUI layer shader on device. This view mirrors the complete panel using
/// renderable SwiftUI primitives. The whole result is composited once and
/// sampled by Metal, so its shell and content deform as a single surface.
struct EntryContextTransitionPanel: View {
    @Environment(\.colorScheme) private var colorScheme

    let kind: EntryContextOverlayKind
    let draft: EntryContextDraft
    let activePaymentPart: Int
    let mainAmountText: String
    let wallets: [CurrencyWallet]
    let currencyCode: String
    let targetHeight: CGFloat

    private var title: String {
        switch kind {
        case .account: "选择账户"
        case .aa: "AA 分摊"
        case .splitPayment: "组合支付"
        case .discount: "优惠"
        case .fee: "手续费"
        case .foreignExpense: "信用卡外币消费"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }

            content
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(height: targetHeight, alignment: .top)
        .background(panelSurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.55), lineWidth: 0.8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityHidden(true)
    }

    private var panelSurface: Color {
        colorScheme == .dark
            ? Color(white: 0.10).opacity(0.94)
            : Color.white.opacity(0.84)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .account:
            VStack(spacing: 8) {
                transitionAccountRow(name: "暂时不记", wallet: nil)
                ForEach(Array(wallets.prefix(6))) { wallet in
                    transitionAccountRow(
                        name: wallet.account?.name ?? wallet.currencyCode,
                        wallet: wallet
                    )
                }
            }
        case .aa:
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text("总人数（含自己）")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Text(
                        draft.aaPeopleText.isEmpty
                            ? "— 人"
                            : "\(draft.aaPeopleText) 人"
                    )
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(
                        draft.hasValidAAPeople ? Color.primary : Color.red
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(minWidth: 52, minHeight: 44)
                    .background(
                        Color.primary.opacity(0.075),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                draft.hasValidAAPeople
                                    ? Color.primary.opacity(0.18)
                                    : Color.red.opacity(0.7),
                                lineWidth: 1
                            )
                    }

                    HStack(spacing: 0) {
                        Image(systemName: "minus")
                            .frame(width: 44, height: 44)
                        Divider().frame(height: 22)
                        Image(systemName: "plus")
                            .frame(width: 44, height: 44)
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(height: 44)
                    .background(Color.primary.opacity(0.09), in: Capsule())
                }
                .padding(14)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack {
                    Text("其他人合计应还")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(MoneyFormatter.string(aaOwedAmount, currencyCode: currencyCode))
                        .font(.headline.monospacedDigit())
                }

                Text("完成")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(
                        LedgerPalette.accent.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(LedgerPalette.accent.opacity(0.38), lineWidth: 0.8)
                    }
            }
        case .splitPayment:
            VStack(spacing: 8) {
                ForEach(Array(draft.paymentParts.indices), id: \.self) { index in
                    HStack(spacing: 10) {
                        Text(walletName(for: draft.paymentParts[index].walletID))
                            .lineLimit(1)
                            .foregroundStyle(LedgerPalette.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Color.primary.opacity(0.07), in: Capsule())

                        Text(
                            draft.paymentParts[index].amountText.isEmpty
                                ? "输入金额"
                                : draft.paymentParts[index].amountText
                        )
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(activePaymentPart == index ? LedgerPalette.accent : .primary)
                        .frame(width: 92, alignment: .trailing)
                    }
                    .padding(10)
                    .background(
                        activePaymentPart == index
                            ? LedgerPalette.accent.opacity(0.08)
                            : Color.primary.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }

                Label("添加账户", systemImage: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LedgerPalette.accent)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
        case .discount:
            HStack {
                Text("优惠金额")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(draft.discountAmountText.isEmpty ? "0" : draft.discountAmountText)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(LedgerPalette.accent)
            }
            .padding(14)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .fee, .foreignExpense:
            EmptyView()
        }
    }

    private func transitionAccountRow(name: String, wallet: CurrencyWallet?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: wallet?.account?.type.symbolName ?? "circle")
                .foregroundStyle(LedgerPalette.accent)
                .frame(width: 28)
            Text(name)
                .font(.subheadline.weight(.semibold))
            Spacer()
            if draft.selectedWalletID == wallet?.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(LedgerPalette.accent)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var aaOwedAmount: Decimal {
        let total = DecimalParser.parse(mainAmountText) ?? 0
        return total * Decimal(draft.aaPeople - 1) / Decimal(draft.aaPeople)
    }

    private func walletName(for id: UUID?) -> String {
        wallets.first(where: { $0.id == id })?.account?.name ?? "选择账户"
    }
}
