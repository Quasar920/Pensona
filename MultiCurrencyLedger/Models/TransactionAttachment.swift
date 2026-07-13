import Foundation
import SwiftData

@Model
final class TransactionAttachment {
    @Attribute(.unique) var id: UUID
    var transactionID: UUID
    var bookID: UUID
    var relativePath: String
    var originalFilename: String
    var mimeType: String
    var byteCount: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        transactionID: UUID,
        bookID: UUID,
        relativePath: String,
        originalFilename: String,
        mimeType: String,
        byteCount: Int,
        createdAt: Date = .now
    ) {
        self.id = id
        self.transactionID = transactionID
        self.bookID = bookID
        self.relativePath = relativePath
        self.originalFilename = originalFilename
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.createdAt = createdAt
    }
}
