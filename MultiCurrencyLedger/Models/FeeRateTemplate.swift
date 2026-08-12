import Combine
import Foundation

enum FeeInputMode: String, Codable, CaseIterable, Sendable {
    case percentage
    case fixedAmount

    var toggleTitle: String {
        switch self {
        case .percentage: "%"
        case .fixedAmount: "定额"
        }
    }

    var inputTitle: String {
        switch self {
        case .percentage: "手续费比例"
        case .fixedAmount: "手续费金额"
        }
    }
}

struct FeeRateTemplate: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var percentage: Decimal
    var applicableKindRawValue: String

    init(
        id: UUID = UUID(),
        name: String,
        percentage: Decimal,
        applicableKind: TransactionKind
    ) {
        self.id = id
        self.name = name
        self.percentage = percentage
        applicableKindRawValue = applicableKind.rawValue
    }

    var applicableKind: TransactionKind {
        TransactionKind(rawValue: applicableKindRawValue) ?? .income
    }
}

enum FeeCalculator {
    static func fee(
        baseAmount: Decimal,
        input: Decimal,
        mode: FeeInputMode,
        currencyCode: String
    ) -> Decimal {
        let raw = mode == .percentage
            ? baseAmount * input / 100
            : input
        return rounded(raw, currencyCode: currencyCode)
    }

    static func rounded(_ amount: Decimal, currencyCode: String) -> Decimal {
        var source = amount
        var result = Decimal.zero
        NSDecimalRound(
            &result,
            &source,
            SupportedCurrency.fractionDigits(for: currencyCode),
            .plain
        )
        return result
    }
}

@MainActor
final class FeeRateTemplateStore: ObservableObject {
    @Published private(set) var templates: [FeeRateTemplate]

    private let defaults: UserDefaults
    private let storageKey = "feeRateTemplates.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([FeeRateTemplate].self, from: data) {
            templates = decoded
        } else {
            templates = [
                FeeRateTemplate(
                    id: UUID(uuidString: "5F44B167-3506-4DE5-A540-CF1496239E46")!,
                    name: "闲鱼手续费",
                    percentage: Decimal(string: "0.38")!,
                    applicableKind: .income
                )
            ]
            persist()
        }
    }

    func templates(for kind: TransactionKind) -> [FeeRateTemplate] {
        templates.filter { $0.applicableKind == kind }
    }

    func save(_ template: FeeRateTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
        } else {
            templates.append(template)
        }
        sortAndPersist()
    }

    func delete(at offsets: IndexSet, kind: TransactionKind) {
        let visible = templates(for: kind)
        let ids = Set(offsets.compactMap { visible.indices.contains($0) ? visible[$0].id : nil })
        templates.removeAll { ids.contains($0.id) }
        persist()
    }

    private func sortAndPersist() {
        templates.sort {
            if $0.applicableKindRawValue != $1.applicableKindRawValue {
                return $0.applicableKindRawValue < $1.applicableKindRawValue
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
