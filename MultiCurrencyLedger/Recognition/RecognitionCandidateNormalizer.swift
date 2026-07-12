import Foundation

struct RecognitionCandidateNormalizer {
    func normalize(
        _ dto: RecognitionCandidateDTO,
        timeZone: TimeZone = .current
    ) -> Result<NormalizedRecognitionCandidate, RecognitionDecisionReason> {
        guard let paid = strictAmount(dto.paidAmount), paid > 0 else {
            return .failure(.invalidAmount)
        }
        guard let currency = SupportedCurrency(rawValue: dto.currencyCode.uppercased()) else {
            return .failure(.unsupportedCurrency)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.isLenient = false
        guard let occurredAt = formatter.date(from: "\(dto.date) \(dto.time)") else {
            return .failure(.invalidDate)
        }

        guard case let .success(original) = optionalAmount(dto.originalAmount),
              case let .success(discountValue) = optionalAmount(dto.discountAmount),
              case let .success(feeValue) = optionalAmount(dto.feeAmount) else {
            return .failure(.invalidAmount)
        }
        let discount = discountValue ?? 0
        let fee = feeValue ?? 0
        guard discount >= 0, fee >= 0, original.map({ $0 > 0 }) ?? true else {
            return .failure(.invalidAmount)
        }

        return .success(.init(
            type: dto.type, paidAmount: paid, originalAmount: original,
            discountAmount: discount, feeAmount: fee, currency: currency,
            occurredAt: occurredAt, merchantOrCounterparty: dto.merchantOrCounterparty,
            sourceAccountHint: dto.sourceAccountHint,
            destinationAccountHint: dto.destinationAccountHint,
            categoryCandidate: dto.categoryCandidate, note: dto.note,
            confidence: dto.confidence
        ))
    }

    private func optionalAmount(_ text: String?) -> Result<Decimal?, RecognitionDecisionReason> {
        guard let text else { return .success(nil) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success(nil) }
        guard let amount = strictAmount(trimmed) else { return .failure(.invalidAmount) }
        return .success(amount)
    }

    private func strictAmount(_ text: String) -> Decimal? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.range(of: #"^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$"#,
                               options: .regularExpression) != nil else {
            return nil
        }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }
}
