# Recognition Entry Loop Implementation Plan

## Goal

Turn the recognition foundation into a safe end-to-end app flow without moving Shortcut complexity into this phase.

## Increments

1. Add an injected HTTPS recognition client. It sends only `RecognitionAPIRequest`, accepts the existing response contract, rejects insecure endpoints and non-2xx/oversized responses, and contains no bundled endpoint or secret.
2. Add an in-app recognition review surface that clearly distinguishes auto-eligible, confirmation-required, and rejected candidates. Nothing is persisted while reviewing.
3. Add a narrow commit service for confirmed expense/income candidates. It resolves the exact wallet/category again, calls `LedgerService`, and remains idempotent at the presentation boundary.
4. Expose the flow through an App Intent suitable for a thin Shortcut. Success returns only after the ledger write so the Shortcut can vibrate once.

## Safety boundaries

- HTTPS only for remote recognition.
- API credentials live outside source control and outside SwiftData financial records.
- Screenshots and OCR text remain in memory.
- Multiple candidates, transfers, refunds, positive fees, ambiguity, or low confidence never auto-write.
- The UI is not allowed to construct ledger transactions directly.
