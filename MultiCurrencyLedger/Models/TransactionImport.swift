import Foundation
import SwiftData

enum TransactionImportPreset: String, CaseIterable, Codable, Identifiable {
    case automatic
    case generic
    case iCost
    case alipay
    case wechat
    case unionPay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: AppLocalization.string( "自动识别")
        case .generic: AppLocalization.string( "通用表格")
        case .iCost: "iCost"
        case .alipay: AppLocalization.string( "支付宝")
        case .wechat: AppLocalization.string( "微信支付")
        case .unionPay: AppLocalization.string( "云闪付")
        }
    }
}

@Model
final class TransactionImportBatch {
    @Attribute(.unique) var id: UUID
    var sourceName: String
    var presetRawValue: String
    var bookID: UUID
    var rowCount: Int
    var importedCount: Int
    var skippedCount: Int
    var errorCount: Int
    var createdAt: Date
    var completedAt: Date?
    var undoneAt: Date?

    init(
        id: UUID = UUID(),
        sourceName: String,
        preset: TransactionImportPreset,
        bookID: UUID,
        rowCount: Int,
        importedCount: Int,
        skippedCount: Int,
        errorCount: Int,
        createdAt: Date = .now,
        completedAt: Date? = .now,
        undoneAt: Date? = nil
    ) {
        self.id = id
        self.sourceName = sourceName
        presetRawValue = preset.rawValue
        self.bookID = bookID
        self.rowCount = rowCount
        self.importedCount = importedCount
        self.skippedCount = skippedCount
        self.errorCount = errorCount
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.undoneAt = undoneAt
    }

    var preset: TransactionImportPreset {
        TransactionImportPreset(rawValue: presetRawValue) ?? .generic
    }
}

@Model
final class TransactionImportFingerprint {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var value: String
    var batchID: UUID
    var transactionID: UUID
    var createdAt: Date

    init(
        id: UUID = UUID(),
        value: String,
        batchID: UUID,
        transactionID: UUID,
        createdAt: Date = .now
    ) {
        self.id = id
        self.value = value
        self.batchID = batchID
        self.transactionID = transactionID
        self.createdAt = createdAt
    }
}
