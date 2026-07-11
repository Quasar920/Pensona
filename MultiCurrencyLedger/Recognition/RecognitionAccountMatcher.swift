import Foundation

enum RecognitionAccountMatch: Equatable {
    case matched(walletID: UUID)
    case ambiguous(walletIDs: [UUID])
    case currencyMismatch
    case unmatched
}

struct RecognitionAccountMatcher {
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

        if let tail = lastFourDigits(in: expandedHint) {
            let tailMatches = options.filter { option in
                let searchable = searchableText(for: option)
                guard searchable.contains(tail) else { return false }
                let banksInHint = aliases.map(\.fullName).filter(expandedHint.contains)
                return banksInHint.isEmpty || banksInHint.contains(where: searchable.contains)
            }
            if !tailMatches.isEmpty {
                return result(for: tailMatches)
            }
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

    private func lastFourDigits(in hint: String) -> String? {
        hint.range(of: #"\d{4}"#, options: .regularExpression).map { String(hint[$0]) }
    }
}
