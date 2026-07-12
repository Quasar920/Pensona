import Foundation

struct RecognitionResponseParser {
    func parse(_ data: Data) throws -> RecognitionEnvelopeDTO {
        guard var text = String(data: data, encoding: .utf8) else {
            throw RecognitionError.invalidResponse
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            guard text.hasSuffix("```"),
                  let firstNewline = text.firstIndex(of: "\n") else {
                throw RecognitionError.invalidResponse
            }
            text.removeLast(3)
            text = String(text[text.index(after: firstNewline)...])
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
