# Task 7 Implementation Report

## Result

Added a sanitized, synthetic recognition acceptance corpus containing exactly eight intended scenarios:

1. CNY expense eligible for auto-entry
2. USD expense eligible for auto-entry through the same account's USD wallet
3. Income blocked when income auto-entry is disabled
4. Transfer requiring confirmation
5. Refund requiring confirmation
6. Pending transaction requiring confirmation
7. Unknown account requiring confirmation
8. Inconsistent discount relationship requiring confirmation

The table-driven gate parses each fixture through `RecognitionResponseParser` and evaluates it with `RecognitionSafetyEvaluator` against deterministic local account/category context and a fixed clock.

## RED evidence

Command:

```text
xcodebuild test -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger -destination 'platform=iOS Simulator,id=1574A408-CD08-49BD-B8EE-09FEBE34CD1B' -only-testing:MultiCurrencyLedgerTests/RecognitionFixtureAcceptanceTests
```

Result: `** TEST FAILED **` during test compilation with `Cannot find 'RecognitionFixtures' in scope`. The acceptance test was added before the fixture corpus.

## GREEN evidence

Focused fixture-gate command: the same command above.

Result: `** TEST SUCCEEDED **`; the single table-driven test passed all eight fixture scenarios.

Full-suite command:

```text
xcodebuild test -project MultiCurrencyLedger.xcodeproj -scheme MultiCurrencyLedger -destination 'platform=iOS Simulator,id=1574A408-CD08-49BD-B8EE-09FEBE34CD1B'
```

Result: `** TEST SUCCEEDED **`; 67/67 tests passed.

## Privacy and scope audit

Command:

```text
rg -n "api[_-]?key|Bearer |https?://|UIImageJPEGRepresentation|pngData\(|write\(to:|LedgerService|LedgerTransaction\(" MultiCurrencyLedger/Recognition MultiCurrencyLedgerTests/Fixtures
```

Result: no matches. The corpus contains generated OCR strings and JSON only; it includes no screenshots, personal names, full card numbers, transaction IDs, addresses, QR codes, endpoint, credential, persistence call, or ledger mutation. The required privacy policy was copied exactly into `docs/recognition-fixtures/README.md`.

## Deviations and self-review

- Used an injected fixed evaluator clock (`2026-07-11 23:59 UTC`) so fixture eligibility does not depend on wall-clock time.
- Preserved the eight fixture names, scenarios, and expected reasons from the brief. Fixture JSON conforms to the hardened parser's strict amount/date schema.
- No production code changed. Self-review confirmed all Task 7 changes are limited to test fixtures, one acceptance test, privacy documentation, and this report.

## Review-finding follow-up

- Replaced the independent `expectsAutoEntry` and `expectedReason` fields with one exhaustive `RecognitionFixtureExpectation` enum. Eligible fixtures must declare an expected `SupportedCurrency`; all other fixtures must declare their exact fallback reason, so eligible metadata cannot drift to a non-eligible reason.
- Added fixed CNY and USD wallet UUIDs and explicit assertions that eligible decisions route to the wallet associated with the fixture's expected currency.
- Added an assertion that each parsed envelope contains exactly one result and replaced unchecked `[0]` indexing with a guarded `first` access.
- Added an explicit assertion that each eligible normalized candidate's currency equals its declared wallet currency.

### Follow-up RED evidence

The updated acceptance test was written before the fixture expectation enum. The focused gate failed to compile with `Value of type 'RecognitionFixture' has no member 'expectation'`.

After reaching green, the USD fixture's expected wallet currency was deliberately changed from `.USD` to `.CNY` and the focused gate was rerun. It produced `** TEST FAILED **` for `RecognitionFixtureAcceptanceTests.testSanitizedFixtureCorpusMatchesExpectedSafetyDecisions()`, proving the wallet-routing and candidate-currency assertions detect incorrect expected routing. The fixture was then restored to `.USD`.

### Follow-up GREEN evidence and self-review

- Restored focused fixture gate: `** TEST SUCCEEDED **`; all eight scenarios passed.
- Full suite: `** TEST SUCCEEDED **`; 67/67 tests passed.
- No fixture-name branching was added; routing is driven only by typed expectation metadata.
- No production code, privacy policy, fixture payload, or scenario outcome changed.
