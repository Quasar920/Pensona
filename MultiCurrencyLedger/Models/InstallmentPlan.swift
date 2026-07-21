import Foundation
import SwiftData

enum InstallmentKind: String, CaseIterable, Codable, Identifiable {
    case consumption, bill

    var id: String { rawValue }
    var title: String {
        self == .consumption ? AppLocalization.string( "消费分期") : AppLocalization.string( "账单分期")
    }
}

@Model
final class InstallmentPlan {
    @Attribute(.unique) var id: UUID
    var name: String
    var bookID: UUID
    var kindRawValue: String
    var totalPrincipal: Decimal
    var totalFee: Decimal
    var installmentCount: Int
    var nextInstallmentIndex: Int
    var startDate: Date
    var nextDueDate: Date
    var sourceWalletID: UUID
    var destinationWalletID: UUID?
    var categoryID: UUID?
    var sourceTransactionID: UUID?
    var merchantOrCounterparty: String?
    var note: String?
    var fractionDigits: Int
    var isPaused: Bool
    var isArchived: Bool
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        bookID: UUID,
        kind: InstallmentKind,
        totalPrincipal: Decimal,
        totalFee: Decimal,
        installmentCount: Int,
        nextInstallmentIndex: Int = 0,
        startDate: Date,
        nextDueDate: Date? = nil,
        sourceWalletID: UUID,
        destinationWalletID: UUID? = nil,
        categoryID: UUID? = nil,
        sourceTransactionID: UUID? = nil,
        merchantOrCounterparty: String? = nil,
        note: String? = nil,
        fractionDigits: Int,
        isPaused: Bool = false,
        isArchived: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.bookID = bookID
        kindRawValue = kind.rawValue
        self.totalPrincipal = totalPrincipal
        self.totalFee = totalFee
        self.installmentCount = installmentCount
        self.nextInstallmentIndex = nextInstallmentIndex
        self.startDate = startDate
        self.nextDueDate = nextDueDate ?? startDate
        self.sourceWalletID = sourceWalletID
        self.destinationWalletID = destinationWalletID
        self.categoryID = categoryID
        self.sourceTransactionID = sourceTransactionID
        self.merchantOrCounterparty = merchantOrCounterparty
        self.note = note
        self.fractionDigits = fractionDigits
        self.isPaused = isPaused
        self.isArchived = isArchived
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var kind: InstallmentKind {
        InstallmentKind(rawValue: kindRawValue) ?? .consumption
    }

    var isCompleted: Bool { completedAt != nil || nextInstallmentIndex >= installmentCount }
}

@Model
final class InstallmentOccurrence {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var generationKey: String
    var planID: UUID
    var installmentIndex: Int
    var scheduledDate: Date
    var principalAmount: Decimal
    var feeAmount: Decimal
    var transactionID: UUID
    var createdAt: Date

    init(
        id: UUID = UUID(),
        generationKey: String,
        planID: UUID,
        installmentIndex: Int,
        scheduledDate: Date,
        principalAmount: Decimal,
        feeAmount: Decimal,
        transactionID: UUID,
        createdAt: Date = .now
    ) {
        self.id = id
        self.generationKey = generationKey
        self.planID = planID
        self.installmentIndex = installmentIndex
        self.scheduledDate = scheduledDate
        self.principalAmount = principalAmount
        self.feeAmount = feeAmount
        self.transactionID = transactionID
        self.createdAt = createdAt
    }
}
