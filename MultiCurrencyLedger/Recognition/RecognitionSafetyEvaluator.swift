import Foundation

struct RecognitionSafetyEvaluator {
    var minimumConfidence: Double
    var matcher: RecognitionAccountMatcher
    var now: () -> Date

    init(
        minimumConfidence: Double = 0.95,
        matcher: RecognitionAccountMatcher = RecognitionAccountMatcher(),
        now: @escaping () -> Date = Date.init
    ) {
        self.minimumConfidence = minimumConfidence
        self.matcher = matcher
        self.now = now
    }

    func evaluate(
        _ dto: RecognitionCandidateDTO,
        ocrText: String,
        context: RecognitionRequestContext,
        allowIncomeAutoEntry: Bool
    ) -> RecognitionDecision {
        let normalizedResult = RecognitionCandidateNormalizer().normalize(dto)
        guard case let .success(candidate) = normalizedResult else {
            if case let .failure(reason) = normalizedResult { return .rejected(reason: reason) }
            return .rejected(reason: .invalidAmount)
        }
        guard candidate.type == .expense || (candidate.type == .income && allowIncomeAutoEntry) else {
            return .needsConfirmation(reason: .unsupportedType, candidate: candidate)
        }
        guard candidate.occurredAt <= now() else {
            return .needsConfirmation(reason: .futureDate, candidate: candidate)
        }

        let riskyTerms = ["退款", "撤销", "处理中", "失败", "还款", "充值", "换汇", "转账"]
        if riskyTerms.contains(where: ocrText.contains) {
            return .needsConfirmation(reason: .riskyStatusText, candidate: candidate)
        }
        guard candidate.feeAmount == 0 else {
            return .needsConfirmation(reason: .feeRequiresConfirmation, candidate: candidate)
        }
        guard containsAmount(candidate.paidAmount, in: ocrText) else {
            return .needsConfirmation(reason: .amountNotVisibleInOCR, candidate: candidate)
        }
        if let original = candidate.originalAmount {
            let tolerance: Decimal = candidate.currency == .JPY ? 1 : 0.01
            let difference = abs(original - candidate.discountAmount - candidate.paidAmount)
            if difference > tolerance {
                return .needsConfirmation(reason: .amountRelationshipMismatch, candidate: candidate)
            }
        }

        let confidence = candidate.confidence
        let values = [confidence.type, confidence.paidAmount, confidence.currencyCode,
                      confidence.account, confidence.category]
        guard minimumConfidence.isFinite, (0...1).contains(minimumConfidence),
              values.allSatisfy({ $0.isFinite && (0...1).contains($0) && $0 >= minimumConfidence }) else {
            return .needsConfirmation(reason: .lowConfidence, candidate: candidate)
        }
        guard let category = candidate.categoryCandidate,
              context.categories.contains(where: {
                  $0.name == category && $0.type == (candidate.type == .expense ? .expense : .income)
              }) else {
            return .needsConfirmation(reason: .categoryUnmatched, candidate: candidate)
        }

        switch matcher.match(hint: candidate.sourceAccountHint, currency: candidate.currency, options: context.accounts) {
        case let .matched(walletID):
            return .autoEligible(walletID: walletID, candidate: candidate)
        case .ambiguous:
            return .needsConfirmation(reason: .accountAmbiguous, candidate: candidate)
        case .currencyMismatch:
            return .needsConfirmation(reason: .currencyWalletMismatch, candidate: candidate)
        case .unmatched:
            return .needsConfirmation(reason: .accountUnmatched, candidate: candidate)
        }
    }

    private func containsAmount(_ amount: Decimal, in text: String) -> Bool {
        // Treat every contiguous ASCII digit/period/comma run as one span. Currency
        // text may touch the span, but an adjacent sign is deliberately rejected.
        let pattern = #"[0-9.,]+"#
        let validToken = try? NSRegularExpression(
            pattern: #"^(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]+)?$"#
        )
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).contains { match in
            guard let tokenRange = Range(match.range, in: text), let validToken else { return false }
            if tokenRange.lowerBound > text.startIndex {
                let previous = text[text.index(before: tokenRange.lowerBound)]
                if previous == "+" || previous == "-" { return false }
            }
            if tokenRange.upperBound < text.endIndex {
                let next = text[tokenRange.upperBound]
                if next == "+" || next == "-" { return false }
            }
            let rawToken = String(text[tokenRange])
            let fullRange = NSRange(rawToken.startIndex..., in: rawToken)
            guard validToken.firstMatch(in: rawToken, range: fullRange)?.range == fullRange else {
                return false
            }
            let token = text[tokenRange].replacingOccurrences(of: ",", with: "")
            return Decimal(string: token, locale: Locale(identifier: "en_US_POSIX")) == amount
        }
    }
}
