import SwiftUI

enum AmountSemanticRole {
    case expense, income, neutral
}

struct AmountSemanticStyle {
    static func color(
        for role: AmountSemanticRole,
        convention: AmountColorConvention
    ) -> Color {
        switch role {
        case .neutral:
            return .primary
        case .expense:
            return convention == .expenseRedIncomeGreen ? .red : .green
        case .income:
            return convention == .expenseRedIncomeGreen ? .green : .red
        }
    }

    static func role(for kind: TransactionKind) -> AmountSemanticRole {
        switch kind {
        case .expense: .expense
        case .income: .income
        case .transfer, .exchange, .adjustment: .neutral
        }
    }
}
