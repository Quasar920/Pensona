import CoreGraphics
import Foundation
import Vision

struct OCRLine: Equatable {
    let text: String
    let boundingBox: CGRect
}

struct OCRDocument: Equatable {
    let lines: [OCRLine]

    var fullText: String {
        lines.map(\.text).joined(separator: "\n")
    }
}

protocol ScreenshotOCRServicing {
    func recognizeText(in image: CGImage) async throws -> OCRDocument
}

struct VisionScreenshotOCRService: ScreenshotOCRServicing {
    func recognizeText(in image: CGImage) async throws -> OCRDocument {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result: Result<OCRDocument, Error>

                do {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    request.recognitionLanguages = ["zh-Hans", "en-US"]
                    // Vision coordinates have their origin at the bottom-left.
                    request.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 0.92)

                    try VNImageRequestHandler(cgImage: image).perform([request])

                    let recognizedLines = (request.results ?? []).compactMap { observation -> OCRLine? in
                        guard let candidate = observation.topCandidates(1).first else { return nil }
                        return OCRLine(text: candidate.string, boundingBox: observation.boundingBox)
                    }
                    let lines = Self.orderedLines(recognizedLines)
                    guard !lines.isEmpty else {
                        throw RecognitionError.noRecognizableText
                    }
                    result = .success(OCRDocument(lines: lines))
                } catch {
                    result = .failure(error)
                }

                // A single exit point guarantees exactly one continuation resumption.
                continuation.resume(with: result)
            }
        }
    }

    static func orderedLines(_ lines: [OCRLine]) -> [OCRLine] {
        let verticallyOrdered = lines.sorted {
            if $0.boundingBox.maxY != $1.boundingBox.maxY {
                return $0.boundingBox.maxY > $1.boundingBox.maxY
            }
            if $0.boundingBox.minX != $1.boundingBox.minX {
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
            if $0.boundingBox.maxX != $1.boundingBox.maxX {
                return $0.boundingBox.maxX < $1.boundingBox.maxX
            }
            if $0.boundingBox.minY != $1.boundingBox.minY {
                return $0.boundingBox.minY > $1.boundingBox.minY
            }
            return $0.text < $1.text
        }

        var rows: [[OCRLine]] = []
        for line in verticallyOrdered {
            if let rowTop = rows.last?.first?.boundingBox.maxY,
               abs(rowTop - line.boundingBox.maxY) <= 0.01 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }

        return rows.flatMap { row in
            row.sorted {
                if $0.boundingBox.minX != $1.boundingBox.minX {
                    return $0.boundingBox.minX < $1.boundingBox.minX
                }
                if $0.boundingBox.maxY != $1.boundingBox.maxY {
                    return $0.boundingBox.maxY > $1.boundingBox.maxY
                }
                if $0.boundingBox.maxX != $1.boundingBox.maxX {
                    return $0.boundingBox.maxX < $1.boundingBox.maxX
                }
                if $0.boundingBox.minY != $1.boundingBox.minY {
                    return $0.boundingBox.minY > $1.boundingBox.minY
                }
                return $0.text < $1.text
            }
        }
    }
}
