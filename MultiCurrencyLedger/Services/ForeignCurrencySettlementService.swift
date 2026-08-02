import Foundation

enum ForeignCurrencySettlementError: LocalizedError, Equatable {
    case invalidExchangeAmounts
    case invalidRepaymentDestination
    case repaymentExceedsOutstanding
    case invalidForeignExpense
    case missingSettlementAmount

    var errorDescription: String? {
        switch self {
        case .invalidExchangeAmounts:
            AppLocalization.string("本位币金额和外币偿还金额必须大于 0")
        case .invalidRepaymentDestination:
            AppLocalization.string("信用卡还款必须转入有效的信用卡币种钱包")
        case .repaymentExceedsOutstanding:
            AppLocalization.string("还款金额不能超过当前币种的未还金额")
        case .invalidForeignExpense:
            AppLocalization.string("外币消费的账户、币种或结算方式无效")
        case .missingSettlementAmount:
            AppLocalization.string("请输入银行实际入账的结算金额")
        }
    }
}

struct ForeignCurrencySettlementService {
    static func isCreditCardRepayment(_ draft: TransactionDraft) -> Bool {
        draft.type == .transfer
            && (draft.transferPurpose == .creditCardRepayment
                || draft.destinationWallet?.account?.type == .creditCard)
    }

    static func exchangeRate(
        settlementAmount: Decimal,
        foreignAmount: Decimal
    ) throws -> Decimal {
        guard settlementAmount > 0, foreignAmount > 0 else {
            throw ForeignCurrencySettlementError.invalidExchangeAmounts
        }
        return settlementAmount / foreignAmount
    }

    static func validateRepayment(_ draft: TransactionDraft) throws {
        guard isCreditCardRepayment(draft) else { return }
        guard let destination = draft.destinationWallet,
              destination.account?.type == .creditCard else {
            throw ForeignCurrencySettlementError.invalidRepaymentDestination
        }
        let repaymentAmount = draft.destinationAmount ?? draft.amount
        guard repaymentAmount > 0 else {
            throw ForeignCurrencySettlementError.invalidExchangeAmounts
        }
        let outstanding = max(Decimal.zero, -destination.balance)
        guard repaymentAmount <= outstanding else {
            throw ForeignCurrencySettlementError.repaymentExceedsOutstanding
        }
        let destinationDiscount = draft.discountWallet?.id == destination.id
            ? (draft.discountAmount ?? 0)
            : 0
        let destinationFee = draft.feeWallet?.id == destination.id
            ? (draft.feeAmount ?? 0)
            : 0
        guard repaymentAmount + destinationDiscount - destinationFee <= outstanding else {
            throw ForeignCurrencySettlementError.repaymentExceedsOutstanding
        }
        if draft.sourceWallet?.currencyCode != destination.currencyCode {
            _ = try exchangeRate(
                settlementAmount: draft.amount,
                foreignAmount: repaymentAmount
            )
        }
    }

    static func validate(_ draft: TransactionDraft) throws {
        try validateForeignExpense(draft)
        try validateRepayment(draft)
    }

    static func validateForeignExpense(_ draft: TransactionDraft) throws {
        guard draft.type == .expense, let mode = draft.foreignSettlementMode else { return }
        guard let wallet = draft.sourceWallet,
              wallet.account?.type == .creditCard,
              let originalAmount = draft.foreignOriginalAmount,
              originalAmount > 0,
              let originalCode = draft.foreignOriginalCurrencyCode,
              SupportedCurrency(rawValue: originalCode) != nil,
              let settlementCode = draft.settlementCurrencyCode,
              SupportedCurrency(rawValue: settlementCode) != nil,
              originalCode != settlementCode else {
            throw ForeignCurrencySettlementError.invalidForeignExpense
        }

        switch mode {
        case .instant:
            guard wallet.currencyCode == settlementCode,
                  let settledAmount = draft.settledAmount,
                  settledAmount > 0,
                  draft.amount == settledAmount else {
                throw ForeignCurrencySettlementError.missingSettlementAmount
            }
            _ = try exchangeRate(
                settlementAmount: settledAmount,
                foreignAmount: originalAmount
            )
        case .repayment:
            guard wallet.currencyCode == originalCode,
                  draft.amount == originalAmount,
                  draft.settledAmount == nil else {
                throw ForeignCurrencySettlementError.invalidForeignExpense
            }
        }
    }
}
