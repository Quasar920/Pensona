# Pensona

Pensona is a local-first personal finance app for iOS. It supports multiple books, accounts, currencies, budgets, assets, bills, savings goals, reporting, and automated bookkeeping workflows.

Built with SwiftUI and SwiftData, the app uses a Liquid Glass visual style and is designed for iOS 26 and later.

## Features

- Multiple books and accounts
- Income, expense, transfer, and adjustment entries
- Multi-currency wallets and exchange rates
- Categories, subcategories, custom icons, and usage-based category management
- Monthly budgets, bills, installments, recurring transactions, and repayment reminders
- Asset overview, savings goals, and statistics dashboards
- CSV/spreadsheet import and export, plus local backup and restore
- Screenshot recognition, Shortcuts, and URL-based quick-entry flows
- Local app lock, CloudKit sync, and multilingual interface support
- Unit tests, UI smoke tests, and performance tests

## Requirements

- macOS
- Xcode Beta (the project currently uses the iOS 26 SDK)
- An iOS 26 or newer simulator or physical device
- An Apple Developer account for device deployment or optional iCloud/CloudKit capabilities

## Getting started

1. Clone the repository:

   ```bash
   git clone https://github.com/Quasar920/Pensona.git
   cd Pensona
   ```

2. Open the Xcode project:

   ```bash
   open MultiCurrencyLedger.xcodeproj
   ```

3. Select the `MultiCurrencyLedger` scheme in Xcode.

4. Select an iOS 26 or newer simulator, or a device with signing configured.

5. Build and run with `⌘R`.

On first launch, the app creates its default categories and required local data structures.

## Testing

Select the `MultiCurrencyLedger` scheme in Xcode and press `⌘U` to run tests.

You can also compile the test targets from the command line:

```bash
xcodebuild \
  -project MultiCurrencyLedger.xcodeproj \
  -scheme MultiCurrencyLedger \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build-for-testing \
  CODE_SIGNING_ALLOWED=NO
```

## Data and privacy

Pensona stores its core financial data locally by default.

- When CloudKit sync is enabled, data syncs through the user's own iCloud account.
- Import, export, and backup are initiated by the user.
- Screenshot recognition and shortcut-entry features should only be used with content you are authorized to process.
- Never commit real financial records, identity documents, card numbers, access tokens, or private keys to the repository.

## Developing with Codex and GPT-5.6

Codex with GPT-5.6 can assist with requirements analysis, implementation, testing, code review, and GitHub publishing for this project. The model is a development aid rather than a runtime dependency: Pensona does not require an OpenAI API key to run.

Recommended workflow:

1. State the goal, affected screen or feature, acceptance criteria, and whether data-model or migration changes are allowed.
2. Ask Codex to inspect the existing implementation, repository state, and relevant test coverage before making changes.
3. Keep changes within the agreed scope; avoid unrelated refactors and preserve SwiftData migration compatibility.
4. Build the project, run relevant tests, and inspect the Git diff after the change.
5. Confirm the commit scope before asking Codex to commit and push to GitHub.

Example prompts:

```text
Review the new-entry flow and identify issues affecting amount calculations and
multi-currency conversion. Explain the cause and impact first; after approval,
fix the issue. Run the relevant unit tests and report changed files and results.
```

```text
Add an accessibility improvement to the Assets screen. Keep the existing Liquid
Glass visual style and do not change the SwiftData model. Build the project when
finished and commit only files related to this improvement.
```

Always review AI-assisted changes manually when they affect:

- Data deletion, migration, or backup/restore
- Amounts, exchange rates, installments, transfers, and book-scoping calculations
- iCloud/CloudKit synchronization and conflict handling
- Secrets, private data, and third-party service configuration
- Git commit contents and the remote push target

For more information about Codex, see the [OpenAI Codex documentation](https://developers.openai.com/codex/).

## Project structure

```text
MultiCurrencyLedger/
├── App/           # App entry point, SwiftData container, navigation, preferences
├── Models/        # SwiftData models and business state
├── Services/      # Bookkeeping, import/export, sync, backup, and domain services
├── Recognition/   # Screenshot recognition and result handling
├── Views/         # SwiftUI screens and shared UI components
├── Utilities/     # Formatting and UI utilities
└── Enums/         # Shared enumerations and types

MultiCurrencyLedgerTests/    # Unit tests
MultiCurrencyLedgerUITests/  # UI smoke and performance tests
docs/                        # Design specifications, plans, and test materials
```

## Contributing

Issues and pull requests are welcome.

Before submitting a change, please ensure that:

- The project builds successfully.
- Relevant tests pass.
- No personal financial data, secrets, or local build artifacts are included.
- The change description is clear and does not contain unrelated files.

## License

This repository does not currently declare a license. Please contact the repository maintainer before using, copying, or distributing the project.
