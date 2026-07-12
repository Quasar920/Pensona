# Recognition Fixture Corpus

This corpus validates OCR-to-decision behavior without storing personal financial screenshots.

- Prefer synthetic OCR text and expected JSON.
- Never commit names, card numbers, transaction IDs, addresses, QR codes, or full screenshots.
- Replace account tails with `1234`, merchants with generic examples, and dates with fixed test dates.
- Every fixture must declare whether auto-entry is allowed and the exact fallback reason.
- A regression fixture is added only after the source screenshot has been discarded or irreversibly sanitized.
