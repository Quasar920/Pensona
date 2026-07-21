import UIKit
import XCTest
@testable import MultiCurrencyLedger

@MainActor
final class CategoryIconStoreTests: XCTestCase {
    private var rootURL: URL!
    private var store: CategoryIconStore!

    override func setUp() {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("category-icons-\(UUID().uuidString)", isDirectory: true)
        store = CategoryIconStore(rootURL: rootURL)
    }

    override func tearDown() {
        if let rootURL { try? FileManager.default.removeItem(at: rootURL) }
    }

    func testSaveGeneratesSafeSquareThumbnailAndOriginal() throws {
        let data = makeImage(size: CGSize(width: 320, height: 180), color: .systemPink)
        let stored = try store.saveImage(data, categoryID: UUID(), renderingMode: .original)
        let thumbnailURL = try store.url(for: stored.thumbnailRelativePath)
        let originalURL = try store.url(for: stored.originalRelativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbnailURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        let thumbnail = try store.thumbnail(relativePath: stored.thumbnailRelativePath)
        XCTAssertEqual(thumbnail.size.width, thumbnail.size.height)
        XCTAssertEqual(Int(thumbnail.size.width), CategoryIconStore.thumbnailPixels)
    }

    func testMonochromeAndPathTraversalProtection() throws {
        let stored = try store.saveImage(
            makeImage(size: CGSize(width: 40, height: 80), color: .systemBlue),
            categoryID: UUID(),
            renderingMode: .monochrome
        )
        XCTAssertNoThrow(try store.thumbnail(relativePath: stored.thumbnailRelativePath))
        XCTAssertThrowsError(try store.url(for: "../escape.png")) {
            XCTAssertEqual($0 as? CategoryIconError, .invalidPath)
        }
        XCTAssertThrowsError(try store.url(for: "/tmp/icon.png"))
    }

    func testDeleteRemovesWholeIconSet() throws {
        let stored = try store.saveImage(
            makeImage(size: CGSize(width: 64, height: 64), color: .black),
            categoryID: UUID(),
            renderingMode: .original
        )
        let directory = try store.url(for: stored.thumbnailRelativePath).deletingLastPathComponent()
        try store.removeIconSet(relativePath: stored.thumbnailRelativePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    private func makeImage(size: CGSize, color: UIColor) -> Data {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            color.setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))
        }
        return image.pngData()!
    }
}
