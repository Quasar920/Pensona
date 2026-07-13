import XCTest
@testable import MultiCurrencyLedger

final class AttachmentStoreTests: XCTestCase {
    func testPNGIsStoredUnderBookAndTransactionDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AttachmentStore(rootURL: root)
        let bookID = UUID()
        let transactionID = UUID()
        let attachmentID = UUID()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        let stored = try store.saveImage(
            png,
            bookID: bookID,
            transactionID: transactionID,
            attachmentID: attachmentID
        )

        XCTAssertEqual(stored.mimeType, "image/png")
        XCTAssertTrue(stored.relativePath.hasSuffix(".png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try store.url(for: stored.relativePath).path))
    }

    func testPathTraversalIsRejected() {
        let store = AttachmentStore(rootURL: FileManager.default.temporaryDirectory)
        XCTAssertThrowsError(try store.url(for: "../outside.jpg")) {
            XCTAssertEqual($0 as? AttachmentError, .invalidPath)
        }
    }
}
