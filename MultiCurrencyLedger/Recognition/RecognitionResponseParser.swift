import Foundation

struct RecognitionResponseParser {
    func parse(_ data: Data) throws -> RecognitionEnvelopeDTO {
        guard var text = String(data: data, encoding: .utf8) else {
            throw RecognitionError.invalidResponse
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            guard let firstNewline = text.firstIndex(of: "\n") else {
                throw RecognitionError.invalidResponse
            }
            text = String(text[text.index(after: firstNewline)...])
            if text.hasSuffix("```") { text.removeLast(3) }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let cleaned = text.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(RecognitionEnvelopeDTO.self, from: cleaned) else {
            throw RecognitionError.invalidResponse
        }
        guard !envelope.results.isEmpty else { throw RecognitionError.emptyResults }
        return envelope
    }
}
