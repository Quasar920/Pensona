import Foundation

enum RecognitionAccountMatch: Equatable {
    case matched(walletID: UUID)
    case ambiguous(walletIDs: [UUID])
    case currencyMismatch
    case unmatched
}

struct RecognitionAccountMatcher {
    private enum TailEvidence {
        case none
        case single(String)
        case conflicting
    }

    private let aliases = [
        (abbreviation: "招行", fullName: "招商银行"),
        (abbreviation: "工行", fullName: "工商银行"),
        (abbreviation: "建行", fullName: "建设银行"),
        (abbreviation: "农行", fullName: "农业银行"),
        (abbreviation: "中行", fullName: "中国银行"),
        (abbreviation: "交行", fullName: "交通银行")
    ]

    func match(
        hint: String?,
        currency: SupportedCurrency,
        options: [RecognitionAccountOption]
    ) -> RecognitionAccountMatch {
        guard let rawHint = hint?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawHint.isEmpty else {
            return .unmatched
        }

        let expandedHint = aliases.reduce(rawHint) { value, alias in
            value.replacingOccurrences(of: alias.abbreviation, with: alias.fullName)
        }
        let sameCurrency = options.filter { $0.currencyCode == currency.rawValue }

        if let result = match(expandedHint: expandedHint, options: sameCurrency) {
            return result
        }
        if match(expandedHint: expandedHint, options: options) != nil {
            return .currencyMismatch
        }
        return .unmatched
    }

    private func match(
        expandedHint: String,
        options: [RecognitionAccountOption]
    ) -> RecognitionAccountMatch? {
        let exactMatches = options.filter { $0.accountName == expandedHint }
        if !exactMatches.isEmpty {
            return result(for: exactMatches)
        }

        switch tailEvidence(in: expandedHint) {
        case let .single(tail):
            let tailMatches = options.filter { option in
                guard case let .single(optionTail) = tailEvidence(in: option.accountName),
                      optionTail == tail else {
                    return false
                }
                let searchable = searchableText(for: option)
                let banksInHint = aliases.map(\.fullName).filter(expandedHint.contains)
                return banksInHint.isEmpty || banksInHint.contains(where: searchable.contains)
            }
            if !tailMatches.isEmpty {
                return result(for: tailMatches)
            }
        case .conflicting:
            return nil
        case .none:
            break
        }

        let aliasMatches = options.filter { option in
            let searchable = searchableText(for: option)
            return aliases.map(\.fullName).contains { bank in
                expandedHint.contains(bank) && searchable.contains(bank)
            }
        }
        return aliasMatches.isEmpty ? nil : result(for: aliasMatches)
    }

    private func result(for options: [RecognitionAccountOption]) -> RecognitionAccountMatch {
        let walletIDs = options.map(\.walletID).sorted { $0.uuidString < $1.uuidString }
        if walletIDs.count == 1 {
            return .matched(walletID: walletIDs[0])
        }
        return .ambiguous(walletIDs: walletIDs)
    }

    private func searchableText(for option: RecognitionAccountOption) -> String {
        [option.accountName, option.accountNote ?? ""].joined(separator: " ")
    }

    private func tailEvidence(in text: String) -> TailEvidence {
        let expression = try! NSRegularExpression(pattern: #"[0-9]+"#)
        let range = NSRange(text.startIndex..., in: text)
        let tails = Set(expression.matches(in: text, range: range).compactMap { match -> String? in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            let digits = String(text[matchRange])
            if (12...19).contains(digits.count) {
                return String(digits.suffix(4))
            }
            guard digits.count == 4, !isPartOfDate(matchRange, in: text) else {
                return nil
            }
            return digits
        })

        if tails.count > 1 { return .conflicting }
        if let tail = tails.first { return .single(tail) }
        return .none
    }

    private func isPartOfDate(_ range: Range<String.Index>, in text: String) -> Bool {
        let separators: Set<Character> = ["-", "/", "."]

        if range.lowerBound > text.startIndex {
            let previous = text.index(before: range.lowerBound)
            if separators.contains(text[previous]) { return true }
        }
        if range.upperBound < text.endIndex, separators.contains(text[range.upperBound]) {
            return true
        }
        return false
    }
}
