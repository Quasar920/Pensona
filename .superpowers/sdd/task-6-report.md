# Task 6 Implementation Report

## Result

Implemented the screenshot recognition coordinator and injected API boundary. One analysis performs one OCR call and one API call, parses the response, and evaluates every returned candidate locally without mutating ledger state.

## Privacy and clock clarifications

- `RecognitionRequestContext` remains local and retains wallet IDs, book metadata, and account notes for deterministic local matching.
- The wire request uses separate minimal `Codable` types. Remote account candidates contain only exact `accountName` and `currencyCode`; remote category candidates contain only `name` and `type`.
- Remote candidates are deduplicated and sorted deterministically before encoding.
- Encoded-payload coverage verifies that wallet/book UUIDs, book name, account note, and their local field names are absent.
- The `now` argument is captured once and drives both `requestedAt` and the evaluator's future-date gate. A deterministic test supplies an evaluator with a conflicting clock to prove the coordinator overrides it for that analysis.

## TDD evidence

1. Added coordinator tests first.
2. Focused test build failed because `RecognitionAPIClient` and `RecognitionAPIRequest` were missing.
3. Added the minimal production implementation.
4. Focused suite passed: 6/6.
5. Full suite passed: 62/62 (baseline 56 plus 6 coordinator tests).

## Phase-boundary audit

`rg -n "LedgerService|LedgerTransaction\(|balance\s*[+\-]?=" MultiCurrencyLedger/Recognition` returned no matches. No endpoint, provider, prompt, API key, screenshot persistence, or ledger write was added. OCR, API, and parser errors propagate unchanged.

## Deviations from abbreviated plan

- `RecognitionAPIRequest.context` is `RecognitionRemoteContext`, not the full local `RecognitionRequestContext`, to satisfy the approved privacy clarification.
- The coordinator replaces the evaluator's clock with the analysis's injected `now`, ensuring a single clock per analysis.
- The tests add explicit one-pass, deterministic clock, deduplication/order, and wire-payload privacy coverage beyond the abbreviated examples.

## Self-review

Reviewed the complete Task 6 diff and found no ledger mutations or out-of-scope infrastructure. The API remains an injected protocol; this phase intentionally provides no concrete network client.

## Batch-safety and cancellation follow-up

### Exact RED evidence

Command:

```text
xcodebuild test -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger -destination 'platform=iOS Simulator,id=1574A408-CD08-49BD-B8EE-09FEBE34CD1B' -only-testing:MultiCurrencyLedgerTests/ScreenshotRecognitionCoordinatorTests
```

Result: `** TEST FAILED **` during test compilation with `Type 'RecognitionDecisionReason' has no member 'multipleCandidates'`. This established that the new batch-safety API and implementation did not exist before production changes.

### Exact GREEN evidence

Focused command: the same `xcodebuild` command above.

Focused result: `** TEST SUCCEEDED **`; 9/9 coordinator tests passed, including two-candidate safety, single-candidate eligibility, cancellation after OCR, and cancellation after API.

Full command:

```text
xcodebuild test -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger -destination 'platform=iOS Simulator,id=1574A408-CD08-49BD-B8EE-09FEBE34CD1B'
```

Full result: `** TEST SUCCEEDED **`; 65/65 tests passed.

### Follow-up behavior and self-review

- Added cancellation checks before OCR, after OCR and before building/transmitting the API request, and after API return and before parsing.
- A cancellation-aware OCR stub cancels its child analysis task before returning; the coordinator throws `CancellationError` and the API call count remains zero.
- A cancellation-ignoring API stub cancels its child analysis task and returns invalid JSON; the coordinator throws `CancellationError` before the parser can translate it to `invalidResponse`.
- When a response contains multiple candidates, all candidates are still evaluated locally so normalized candidate data and stricter reasons are retained. Only `.autoEligible` results are downgraded to `.needsConfirmation(reason: .multipleCandidates, candidate: ...)`.
- Re-reviewed the diff for one-pass behavior, error propagation, remote-payload minimization, and ledger mutation. No additional OCR/API calls, payload fields, persistence, or ledger writes were introduced.

## Final re-review follow-up

- Added a request preflight cancellation check directly after `RecognitionAPIRequest` construction and directly before `apiClient.recognize(request)`. The existing post-OCR and post-API checks remain.
- Did not add an injected context-construction cancellation seam: context/request construction is synchronous on the main actor with no suspension point, so external cancellation cannot interleave during that block. Adding a test-only hook would unnecessarily pollute the production coordinator API.
- Verified source adjacency with an `awk` audit requiring the line immediately before `apiClient.recognize(request)` to contain `try Task.checkCancellation()`; result: `adjacency_audit=clean`.
- Added a mixed two-result characterization test. It proves an otherwise eligible result becomes `.multipleCandidates` with normalized data retained, while a transfer's stricter `.unsupportedType` reason and normalized data are preserved.
- The mixed-result test passed before the adjacency-only production change, confirming the existing batch downgrade logic already had the requested selective behavior.
- Focused coordinator suite: `** TEST SUCCEEDED **`, 10/10 passed.
- Full suite: `** TEST SUCCEEDED **`, 66/66 passed.
- Final self-review found no extra OCR/API pass, remote payload expansion, error translation, persistence, or ledger mutation.
