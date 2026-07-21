import SwiftData
import SwiftUI

struct ExchangeRateListView: View {
    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.CNY.rawValue
    @Query(sort: \ExchangeRate.currencyCode) private var rates: [ExchangeRate]
    @State private var editingCurrency: SupportedCurrency?

    private var relevantRates: [ExchangeRate] {
        rates.filter { $0.baseCurrencyCode == baseCurrencyCode }
    }

    var body: some View {
        List {
            Section {
                Text("输入 1 单位外币可折合多少 \(baseCurrencyCode)。本位币自身固定为 1。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("相对 \(baseCurrencyCode) 的汇率") {
                ForEach(SupportedCurrency.allCases.filter { $0.rawValue != baseCurrencyCode }) { currency in
                    Button { editingCurrency = currency } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(currency.rawValue).foregroundStyle(.primary)
                                Text(currency.localizedName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let rate = relevantRates.first(where: { $0.currencyCode == currency.rawValue }) {
                                VStack(alignment: .trailing) {
                                    Text(NSDecimalNumber(decimal: rate.rate).stringValue)
                                        .monospacedDigit().foregroundStyle(.primary)
                                    Text(rate.updatedAt, format: .dateTime.year().month().day())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } else {
                                Text("未设置").foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("汇率管理")
        .sheet(item: $editingCurrency) { currency in
            EditExchangeRateView(currency: currency, baseCurrencyCode: baseCurrencyCode)
        }
    }
}

private struct EditExchangeRateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var allRates: [ExchangeRate]
    let currency: SupportedCurrency
    let baseCurrencyCode: String
    @State private var rateText = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("外币", value: currency.rawValue)
                    LabeledContent("本位币", value: baseCurrencyCode)
                    TextField("1 \(currency.rawValue) = ? \(baseCurrencyCode)", text: $rateText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("设置汇率")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let existing = existingRate { rateText = "\(existing.rate)" }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
            }
            .alert("无法保存", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("好") {} } message: { Text(errorMessage ?? AppLocalization.string("未知错误")) }
        }
    }

    private var existingRate: ExchangeRate? {
        allRates.first { $0.currencyCode == currency.rawValue && $0.baseCurrencyCode == baseCurrencyCode }
    }

    private func save() {
        guard let value = DecimalParser.parse(rateText), value > 0 else {
            errorMessage = AppLocalization.string( "请输入大于 0 的有效汇率")
            return
        }
        do {
            if let existingRate {
                existingRate.rate = value
                existingRate.updatedAt = .now
                existingRate.sourceRawValue = ExchangeRateSource.manual.rawValue
            } else {
                context.insert(ExchangeRate(
                    currencyCode: currency.rawValue,
                    baseCurrencyCode: baseCurrencyCode,
                    rate: value
                ))
            }
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
