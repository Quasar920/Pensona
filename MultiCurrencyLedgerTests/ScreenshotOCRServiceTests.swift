import UIKit
import XCTest
@testable import MultiCurrencyLedger

final class ScreenshotOCRServiceTests: XCTestCase {
    func testOrdersLinesTopToBottomAndLeftToRightDeterministically() {
        let lower = OCRLine(text: "C", boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.1))
        let right = OCRLine(text: "B", boundingBox: CGRect(x: 0.6, y: 0.7, width: 0.2, height: 0.1))
        let left = OCRLine(text: "A", boundingBox: CGRect(x: 0.1, y: 0.695, width: 0.2, height: 0.1))

        let ordered = VisionScreenshotOCRService.orderedLines([lower, right, left])

        XCTAssertEqual(ordered, [left, right, lower])
    }

    func testRecognizesTransactionTextFromGeneratedScreenshot() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200))
        let image = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 900, height: 1200))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 72, weight: .semibold),
                .foregroundColor: UIColor.black
            ]
            "支付成功\n星巴克\nCNY 85.00".draw(
                in: CGRect(x: 80, y: 220, width: 740, height: 500),
                withAttributes: attributes
            )
        }

        let document = try await VisionScreenshotOCRService().recognizeText(in: image.cgImage!)

        XCTAssertTrue(document.fullText.contains("星巴克"))
        XCTAssertTrue(document.fullText.contains("85.00"))
    }
}
