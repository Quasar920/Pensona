import Foundation
import SwiftData

enum AASplitCalculationMode: String, CaseIterable, Codable, Identifiable {
    case equal
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .equal: "AA 均分"
        case .custom: "自定义金额"
        }
    }
}

enum AASplitStatus: String, Equatable {
    case pending
    case partial
    case settled

    var title: String {
        switch self {
        case .pending: "待收款"
        case .partial: "部分收款"
        case .settled: "已结清"
        }
    }
}

@Model
final class AASplit {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var originalTransactionID: UUID
    var otherPeopleCount: Int
    var calculationModeRawValue: String
    var othersOwedAmount: Decimal
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        originalTransactionID: UUID,
        otherPeopleCount: Int,
        calculationMode: AASplitCalculationMode,
        othersOwedAmount: Decimal,
        note: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.originalTransactionID = originalTransactionID
        self.otherPeopleCount = otherPeopleCount
        calculationModeRawValue = calculationMode.rawValue
        self.othersOwedAmount = othersOwedAmount
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var calculationMode: AASplitCalculationMode {
        AASplitCalculationMode(rawValue: calculationModeRawValue) ?? .equal
    }
}

@Model
final class AASettlement {
    @Attribute(.unique) var id: UUID
    var splitID: UUID
    @Attribute(.unique) var recoveryTransactionID: UUID
    var amount: Decimal
    var createdAt: Date

    init(
        id: UUID = UUID(),
        splitID: UUID,
        recoveryTransactionID: UUID,
        amount: Decimal,
        createdAt: Date = .now
    ) {
        self.id = id
        self.splitID = splitID
        self.recoveryTransactionID = recoveryTransactionID
        self.amount = amount
        self.createdAt = createdAt
    }
}

struct AASplitDraft: Equatable {
    var otherPeopleCount: Int
    var calculationMode: AASplitCalculationMode
    var othersOwedAmount: Decimal
    var note: String?
    var basedOnAmount: Decimal

    init(
        otherPeopleCount: Int,
        calculationMode: AASplitCalculationMode,
        othersOwedAmount: Decimal,
        note: String? = nil,
        basedOnAmount: Decimal
    ) {
        self.otherPeopleCount = otherPeopleCount
        self.calculationMode = calculationMode
        self.othersOwedAmount = othersOwedAmount
        self.note = note
        self.basedOnAmount = basedOnAmount
    }

    init(split: AASplit, totalAmount: Decimal) {
        self.init(
            otherPeopleCount: split.otherPeopleCount,
            calculationMode: split.calculationMode,
            othersOwedAmount: split.othersOwedAmount,
            note: split.note,
            basedOnAmount: totalAmount
        )
    }
}

struct AASplitAmounts: Equatable {
    let totalAmount: Decimal
    let othersOwedAmount: Decimal
    let myShareAmount: Decimal
}

struct AASplitSummary: Equatable {
    let othersOwedAmount: Decimal
    let collectedAmount: Decimal

    var remainingAmount: Decimal { max(0, othersOwedAmount - collectedAmount) }

    var status: AASplitStatus {
        if collectedAmount <= 0 { return .pending }
        return remainingAmount > 0 ? .partial : .settled
    }

    var progress: Double {
        guard othersOwedAmount > 0 else { return 0 }
        return min(
            max(NSDecimalNumber(decimal: collectedAmount / othersOwedAmount).doubleValue, 0),
            1
        )
    }
}
