# Receipt Entry Sheet Rebuild — Design QA

- Date: 2026-08-14
- Source visual truth: `/Users/ian/Downloads/ChatGPT Image 2026年8月14日 00_05_25.png`
- Product constraints: `/Users/ian/Downloads/小票风记账编辑器 Sheet UI 改造方案.md`
- Final single-Sheet light implementation: `/Users/ian/.codex/worktrees/6c28/记账Vibe Coding/.build/qa-receipt-entry-v2/receipt-single-light.png`
- Final single-Sheet dark implementation: `/Users/ian/.codex/worktrees/6c28/记账Vibe Coding/.build/qa-receipt-entry-v2/receipt-single-dark.png`
- Source/implementation comparison: `/Users/ian/.codex/worktrees/6c28/记账Vibe Coding/.build/qa-receipt-entry/reference-vs-implementation.png`
- Viewport: iPhone 17 Pro Simulator, 402 x 874 points, 1206 x 2622 pixels at 3x, Simplified Chinese, light appearance.
- State: expense, takeaway selected, CNY 0, populated sample account and full expense category set.

## Findings

No actionable P0, P1, or P2 mismatch remains in the rebuilt entry-sheet scope.

The final comparison preserves the reference hierarchy in one 92%-height Sheet: a separately rendered warm-white receipt, a continuous full-width 13 x 11-point torn edge below the drag handle, a four-way black selected segment, three metadata rows, five fixed category columns, centered category/amount, six expense settings, the cash-register keypad, and equal-width actions. All content metrics are reduced together so the entire receipt remains visible without scrolling.

## Required Fidelity Surfaces

- Geometry: outer shell and torn paper are separate surfaces. The shell keeps a 30-point continuous radius and the paper alone owns the repeated triangular top edge.
- Typography and copy: all field and setting labels are Chinese. `CNY` remains as the currency code. The removed editor title, decorative English, type label, extra labels, and duplicate account entrance do not appear.
- Categories: normal-size layout is exactly five columns with 7-point gaps and approximately square 64-point cells. Icons remain above labels. The selected takeaway tile uses a 2-point black outline and top-right check without a black fill.
- Color and separators: the receipt and category tiles use `#F7F5EF`; dividers use low-contrast 3/3 dashed strokes; outlines stay light except for active selection and the primary completion action.
- Keypad: the left grid is four columns by four rows; zero spans two columns; the right delete key spans all four rows and retains long-press clear; the final action row is split equally and the completion half is black.
- Assets: existing category artwork is preserved. No placeholder art or replacement emoji was introduced.

## Interaction Verification

- Existing `TransactionFormState`, `EntrySessionState`, validation, continuous-entry, transfer/exchange, foreign-currency, credit-card repayment and save callbacks remain behind the new view contract.
- Category root/child selection, expansion, creation, edit, delete, move, long-press and reorder continue through the existing category pager; only the tile surface changed.
- AA, discount, split payment and fee rows use the existing `EntryContextPresentationState`, drafts, panels, fee templates and shared keypad input.
- Simulator Debug build passed.
- Focused state/model tests passed: `TransactionFormStateTests`, `EntrySessionStateTests`, `EntryCalculationTests`, and `EntryContextPresentationStateTests`.
- Light and dark simulator captures confirm that the receipt itself uses one appearance-invariant warm-white UI; only the original page and status area behind the Sheet follow system appearance.
- Drag tracking now applies raw translation without per-frame spring interpolation, and the backdrop fades from the same live drag progress.

## Comparison History

1. The rejected implementation treated the outer Sheet itself as torn paper and retained an unrelated glass editor hierarchy. That presentation layer was removed.
2. The first rebuilt capture had visibly gray category fills. Category cards were corrected to the same warm-white paper token, leaving borders to carry structure and selection.
3. The first secondary-panel bridge reused a reduced legacy overlay. It was replaced before handoff with the current `EntryContextPresentationState` panels so AA, split payment, discount, fee validation and fee templates remain intact.
4. The second correction removed the receipt scroll view, compacted all content as one density system, removed the hidden NavigationStack background that flattened the tear, and verified the complete single-frame result in both appearances.

## Follow-up Polish

No P3 visual follow-up is required for the requested rebuild. Secondary panel styling remains intentionally unchanged, per scope.

final result: passed

---

# Asset Bank-Card Capsule Rows — Design QA

- Date: 2026-08-13
- Source visual truth: `/var/folders/76/x90l9tx10xqgf2tk6n65w8_c0000gn/T/codex-clipboard-b1070c0c-52f8-4676-bdf4-1359438fd4cf.png`
- Final light implementation: `/Users/ian/.codex/worktrees/6c28/记账Vibe Coding/.build/qa-asset-capsules/assets-light-final.png`
- Final dark implementation: `/Users/ian/.codex/worktrees/6c28/记账Vibe Coding/.build/qa-asset-capsules/assets-dark-final.png`
- Focused bank-card crop: `/Users/ian/.codex/worktrees/6c28/记账Vibe Coding/.build/qa-asset-capsules/assets-dark-bank-final.png`
- Focused source/implementation comparison: `/Users/ian/.codex/worktrees/6c28/记账Vibe Coding/.build/qa-asset-capsules/reference-vs-implementation-final.png`
- Viewport: iPhone 17 Pro Simulator, 402 x 874 points, 1206 x 2622 pixels at 3x, Simplified Chinese; verified in light and dark appearance.
- Density normalization: source is 1000 x 400 pixels with no declared device density; it was normalized to 1206 x 482 for the focused comparison. The implementation remained at native 3x density; its 1206 x 850 focused crop was compared at equal width. CSS size is not applicable to this native SwiftUI screen.
- State: populated asset dashboard with two bank-card accounts; balances visible.

## Findings

No actionable P0, P1, or P2 visual mismatch remains in the requested scope.

The reference's independent dark capsules, full-width rounded geometry, subtle outline, left identity, right-aligned value, and separated vertical rhythm are preserved. The implementation intentionally uses a 52-point minimum height instead of copying the thinner web row because this is a native iOS control with a full-row tap target. The requested looser rhythm is represented by a 14-point inter-card gap. Product copy, account icons, and balances remain app-owned content rather than copied task-row content.

## Required Fidelity Surfaces

- Fonts and typography: existing OneTsu account and amount styles are preserved. Account names remain semibold system text; balances remain semibold monospaced digits with single-line scaling. No wrapping or truncation is visible at the verified viewport.
- Spacing and layout rhythm: cards use the existing 16-point page margin, 18-point internal horizontal padding, 52-point minimum height, 26-point continuous corner radius, and 14-point vertical gap. Both cards align to the same full width and keep a larger gap than the reference.
- Colors and visual tokens: cards reuse `LedgerPalette.surface`, adaptive hairline borders, and the existing restrained elevation. Light and dark captures preserve readable contrast without introducing a new accent color.
- Image quality and asset fidelity: the reference contains only standard UI icons and no raster imagery. The implementation uses the app's existing SF Symbols; no placeholder, handcrafted SVG, CSS art, or generated asset was introduced.
- Copy and content: account names, balances, group subtotal, and optional last-four information remain sourced from the app. Reference-specific supplier/task copy was not imported.

## Interaction Verification

- Tapping a capsule opens the existing account detail view.
- Long-press context-menu editing and the named accessibility edit action remain attached to each account button.
- Press feedback scales only capsule cards and respects Reduce Motion.
- `MultiCurrencyLedgerSmokeUITests.testBillSwipeAndAssetDetail()` passed after exercising the root tab, the capsule tap, and the account-detail navigation.
- `AssetDashboardServiceTests` passed all 3 tests, including account and optional-book transaction scoping.
- The simulator build succeeded. Browser-console checks are not applicable to this native SwiftUI implementation; the initial interaction run exposed a SwiftData SQLite predicate abort, which was removed and then reverified by the passing UI test.

## Full-View And Focused Evidence

- Full-view evidence: the final light and dark implementation screenshots show the capsules in the complete asset-page hierarchy and confirm that neighboring asset groups remain unchanged.
- Focused evidence: the combined comparison places the exact source component above the final dark bank-card region at equal width. The capsule silhouette, surface separation, left/right alignment, and intentionally looser card spacing are directly visible, so no additional micro-crop was required.

## Comparison History

1. Initial implementation used 64-point two-line cards. The first focused comparison showed the cards were materially taller than the reference and diluted the capsule silhouette (P2).
2. The cards were revised to a 52-point single-line layout, with optional card-tail information inline only when present. Post-fix light/dark captures show the intended capsule ratio while retaining a native tap target.
3. The first account-tap run reached the capsule but exposed an existing SwiftData abort in a nested relationship predicate. The account transaction query was changed to database-side date sorting plus equivalent in-memory account/book filtering. All service tests and the repeated UI navigation test passed afterward.

## Follow-up Polish

No P3 follow-up is required for the requested capsule treatment.

final result: passed

---

# Bottom Navigation Motion-Only Correction — Physical Device Gate

- Date: 2026-08-13
- Source visual truth: `/Users/ian/Downloads/ScreenRecording_08-13-2026 10-51-10_1.mov`
- Source motion contact sheet: `/Users/ian/.codex/worktrees/6c28/记账Vibe Coding/.build/qa-bottom-bar-video-reference/reference-contact-sheet.png`
- Source resting frame: `/Users/ian/.codex/worktrees/6c28/记账Vibe Coding/.build/qa-bottom-bar-video-reference/reference-resting-ledger.png`
- User-reported failure screenshot: `/var/folders/76/x90l9tx10xqgf2tk6n65w8_c0000gn/T/codex-clipboard-dd7e5f8d-99ff-45ce-962f-7bd7625b85b4.png`
- Corrected physical-device screenshot: `/Users/ian/.codex/worktrees/6c28/记账Vibe Coding/.build/qa-bottom-bar-device-fix/device-fixed-height.png`
- Focused physical-device crop: `/Users/ian/.codex/worktrees/6c28/记账Vibe Coding/.build/qa-bottom-bar-device-fix/device-bottom-bar.png`
- Latest fixed-position label capture: `/Users/ian/.codex/worktrees/6c28/记账Vibe Coding/.build/qa-bottom-bar-label-below/device-selected-assets.png`
- Latest focused navigation crop: `/Users/ian/.codex/worktrees/6c28/记账Vibe Coding/.build/qa-bottom-bar-label-below/device-selected-assets-bottom.png`
- Full-view failure/fix evidence: `/Users/ian/.codex/worktrees/6c28/记账Vibe Coding/.build/qa-bottom-bar-device-fix/device-failure-vs-fixed.png`
- Focused source/device evidence: `/Users/ian/.codex/worktrees/6c28/记账Vibe Coding/.build/qa-bottom-bar-device-fix/reference-vs-device.png`
- Viewport: physical iPhone 17 Pro (`L-points1`), 402 x 874 points, 1206 x 2622 pixels at 3x, light appearance, Simplified Chinese.
- State: ledger selected at rest; automated gesture starts on ledger, crosses the centered add button, and releases on reports.

## Findings

No actionable P0, P1, or P2 issue remains in the corrected scope.

The source video is used only as motion/material reference. Its trailing add-button geometry and always-visible labels were explicitly excluded. The existing OneTsu layout is restored: two destinations on each side of the fixed 52-point centered add button.

The navigation rail now has an explicit 62-point height. The selected lens is one persistent, strictly bounded 84 x 50-point material view. Its center tracks the finger directly across gaps and across the center action, so selection does not disappear and a new bubble is not recreated at each destination. The page selection commits only when the gesture ends.

## Required Fidelity Surfaces

- Layout: existing page padding, 62-point capsule rail, centered 52-point black add button, and two-by-two destination grouping are preserved. The corrected physical-device capture shows the rail anchored at the bottom without obscuring ledger content.
- Typography: every destination keeps a fixed 52-point slot. Inactive titles are visually hidden while preserving layout; the active title fades and scales into the reserved line directly below its icon. No icon or neighboring control shifts when selection changes.
- Material: the persistent selected lens uses a bounded system material with restrained neutral overlays and adaptive strokes. Its content sits in a higher compositing layer so the selected blue icon and title remain crisp.
- Icons and copy: existing SF Symbols and localized OneTsu destination names are unchanged.

## Interaction Verification

- Direct tracking disables interpolation for the lens center during the drag, giving 1:1 finger movement.
- Nearest-midpoint hover changes animate only the active icon/title expansion; they do not change the page.
- Releasing commits the destination and springs the lens from the release point into the destination's final frame.
- A drag must start inside a destination hit region, so the center add action remains independent.
- No navigation haptic call remains in the component.
- Reduce Motion falls back to the existing reduced animation.
- UI test passed: `MultiCurrencyLedgerSmokeUITests.testBottomNavigationKeepsCenteredEntryAndSupportsContinuousDrag()`. It now asserts that the center action remains in the lower quarter of the display and shares the tab-row vertical center, preventing recurrence of the full-height rail.
- The same UI test also records all four tab centers plus the add-button center before dragging, then verifies every coordinate is unchanged after selecting reports.
- Build passed for both the iPhone 17 Pro Simulator and physical `L-points1`; the corrected build was installed, launched, and captured from the physical device.

## Comparison History

1. The first pass incorrectly copied the source layout, moving the add action to the trailing edge and exposing every title. That was rejected and fully removed.
2. The next pass introduced a P0 physical-device regression: the flexible navigation ZStack accepted the safe-area inset's full-height proposal, so the rail capsule expanded over almost the entire screen. Simulator-only review failed to catch the problem before handoff.
3. The rail was changed from a minimum height to an explicit 62-point height, and the selected lens was changed to a strictly bounded system-material surface. The physical-device screenshot now shows normal ledger content with the rail confined to the bottom edge.
4. The automated test gained vertical-position assertions and again passed the ledger-to-reports drag, center alignment, bottom anchoring, and release-time destination checks.
5. Active labels were moved from the icon's trailing edge to a permanently reserved line below the icon. Fixed-width tab slots and coordinate assertions remove selection-dependent horizontal movement; the latest physical-device capture confirms the assets label below the unchanged asset icon position.

## Follow-up Polish

No P3 follow-up is required for the requested effect.

final result: passed

---

# Historical Design QA Archive

# Home Interaction Optimization — Design QA

- Source visual truth: `/Users/ian/长期需要/记账Vibe Coding/.build/qa/home-populated-passed-2.png` plus the user's round-two interaction specification
- Implementation screenshot: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-round2/final-home.png`
- Viewport: iPhone 16, 393 × 852 points, 3× capture
- State: populated current-month home, light appearance
- Full-view comparison evidence: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-round2/round2-comparison.png`
- Focused-state evidence:
  - book switcher: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-round2/final-book-switcher.png`
  - hidden balance: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-round2/hidden-balance.png`
  - historical month: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-round2/final-previous-month.png`
  - future empty state: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-round2/final-future-month.png`
  - filtered all-records page: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-round2/final-all-records.png`
  - dark appearance: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-round2/final-dark.png`

## Findings

No actionable P0, P1, or P2 issues remain.

The revised screen preserves the original mist-white card system while making the three navigation layers distinct: book scope at the top, time scope between balance and records, and product destinations in the bottom bar. The blue plus remains the only primary create action.

## Required Fidelity Surfaces

- Fonts and typography: native San Francisco hierarchy is preserved. The book name and month use semibold controls, the balance remains the only display-scale number, and date headers are deliberately quieter than transaction titles.
- Spacing and layout rhythm: the balance card was shortened, inter-section spacing reduced to 12 points, and transaction rows tightened to 54 points. Four sample records and both date groups now remain visible above the floating navigation without clipping.
- Colors and visual tokens: the existing cool-gray background, white/material cards, system blue, semantic income green, and restrained expense red are retained. Dark mode uses the same semantic hierarchy with adaptive borders.
- Image quality and icon fidelity: all interface imagery uses SF Symbols. No brand assets, emoji, handcrafted icons, or raster placeholders were introduced.
- Copy and content: the balance helper now accurately states `所有资产已折算为 CNY`; current, historical, future, hidden-balance, and empty-book states all have specific Chinese copy.

## Product Logic Review

- A persistent `LedgerBook` model scopes accounts, balances, entry-wallet choices, and transactions.
- Existing accounts are migrated into `日常账本`; switching to another book refreshes balance, records, assets, and the add-entry wallet list.
- The balance uses `ValuationService`, so every enabled wallet is converted to the configured base currency. Missing rates are surfaced instead of silently misrepresenting the total.
- Balance privacy is persisted and toggles between the formatted amount and `¥••••••`.
- Month arrows, the wheel month picker, historical labels, and future empty states all update the same month selection.
- `全部` pushes a month-and-book-filtered page titled `YYYY年M月 · 全部记录`.
- The bottom navigation contains three equal-width destination tabs plus one equal-width primary add action; the redundant `记账` tab is removed.

## Comparison History

1. Initial implementation retained too much vertical space and allowed the fourth record to sit under the floating navigation (P2). The balance card, section rhythm, group spacing, and row height were tightened; the final capture shows all four records fully visible.
2. The first filtered-record capture inherited the simulator's English `Back` label (P2 localization drift). A custom native chevron back control with a Chinese accessibility label replaced it.
3. State verification covered the book switcher, hidden balance, previous month, future month, filtered all-records destination, and dark appearance. No clipping, horizontal overflow, or ambiguous duplicate create actions remain.

## Verification

- Build: passed on iPhone Simulator target.
- Tests: 9 passed, including cross-currency home valuation and duplicate book-name validation.
- Data states: populated, empty book, current month, previous month, future month, and hidden balance exercised through debug-only preview state hooks.

## Follow-up Polish

- P3: deleting a book is intentionally not exposed yet because a product decision is needed for moving or deleting its accounts and transactions.
- P3: the savings tab remains an existing placeholder until savings-goal persistence is defined.

final result: passed

# OneTsu Morning Mist UI — Phase 0 Baseline (First Eight Tasks)

- Date: 2026-08-10
- Scope: the first eight tasks in roadmap phase 0 only.
- Deferred by product decision: Debug/Release build gate, full unit suite, UI smoke suite, performance journey, and refreshed P0/P1/P2/deferred register.
- Baseline device: dedicated clean iPhone 17 Pro Simulator, iOS 26.5 (`57316310-F6E5-4BDC-920D-69A6F402013A`).
- App source: the existing current Debug simulator artifact; no new build or test gate was run for this capture.
- Locale and sample state: Simplified Chinese, deterministic in-memory sample data, system `large` content size unless stated otherwise.
- Artifact root: `/Users/ian/.codex/worktrees/6c28/记账Vibe Coding/.build/qa-onetsu-morning-mist-phase0`.

## Workspace Inventory and Boundary

The working tree is intentionally dirty and contains two independently classified scopes. No file was cleaned, reverted, staged, committed, or pushed while freezing this baseline.

Morning Mist visual-convergence scope:

- Root and shared surfaces: `RootTabView.swift`, `LedgerGlassComponents.swift`, `LedgerBottomBar.swift`, and `EntryExpansionContainer.swift` visual hunks.
- Ledger: `HomeView.swift`, `BillPageComponents.swift`, `BillSearchView.swift`, and `PensonaDashboardComponents.swift`.
- Assets: `AccountListView.swift` and `AssetDashboardView.swift`.
- Plans and reports: `SavingsGoalViews.swift` and `StatisticsDashboardView.swift`.
- Entry: `EntryAmountPanel.swift`, `EntryContextGenieTransition.swift`, `TransactionFormSections.swift`, `UnifiedEntryView.swift`, and `CenteredGenieCard.swift`.
- Settings presentation: the grouped-list and footer presentation hunks in `SettingsView.swift`.
- Visual resources and verification: Ioskeley Mono font resources, `Info.plist` font declarations, the UI smoke-test expectation changes, and `2026-08-10-onetsu-morning-mist-ledger-ui-design.md`.

Phase 1 functional scope, excluded from the visual-change classification:

- `AppCapabilities.swift`, `AppLaunchCoordinator.swift`, and `AppLaunchCoordinatorTests.swift`.
- App bootstrap/recovery, external-URL queueing, migration snapshot exposure, and capability gating hunks.
- Brand/iCloud availability copy, URL/Shortcut error copy, module-name compatibility, and README updates.

Shared files (`project.pbxproj`, `RootTabView.swift`, `Localizable.xcstrings`, and `SettingsView.swift`) contain both scopes; their hunks were reviewed and are recorded above rather than treating the entire dirty worktree as one visual change.

## Root Page Baselines

| Surface | Light | Dark |
|---|---|---|
| Ledger | `ledger-light.png` | `ledger-dark.png` |
| Assets | `assets-light.png` | `assets-dark.png` |
| Plans | `plans-light.png` | `plans-dark.png` |
| Reports | `reports-light.png` | `reports-dark.png` |

The four light captures are combined in `contact-roots-light.png`; the four dark captures are combined in `contact-roots-dark.png`.

## Entry Baselines

| State | Light | Dark |
|---|---|---|
| Base entry form | `entry-basic-light.png` | `entry-basic-dark.png` |
| Expanded category layer | `entry-expanded-light.png` | `entry-expanded-dark.png` |

Combined comparison: `contact-entry.png`.

## Required State Coverage

- Normal populated state: `ledger-light.png` and `ledger-dark.png`.
- Empty state: `state-empty-light.png`.
- Loading state: `state-loading-light.png`, supplemented by `loading-sequence.mov` and `contact-loading-10fps.png`.
- Error state: `state-error-light.png`, showing the in-app unsupported-link error and recovery action.
- Accessibility text state: `state-dynamic-type-accessibility3-light.png`, captured at `accessibility-extra-extra-extra-large`.
- Combined state comparison: `contact-states.png`.

Visual inspection confirmed that every root destination changed correctly, light and dark appearances differ, the entry expansion is not a duplicate capture, and empty/error/accessibility states are active. Frame-by-frame launch inspection also records a current limitation: the visible loading transition is the system white launch surface before the populated ledger appears; the custom in-app preparing view is too brief to produce a stable frame in this build. This is baseline evidence, not a pass claim for the deferred issue register.

phase result: first eight baseline tasks complete; final five execution tasks and all phase acceptance gates remain deferred

# Full Liquid Glass Redesign — Phase 0 Baseline

- Date: 2026-07-20
- Approved specification: `docs/superpowers/specs/2026-07-20-full-liquid-glass-ui-interaction-redesign-design.md`
- Approved implementation plan: `docs/superpowers/plans/2026-07-20-full-liquid-glass-ui-interaction-redesign.md`
- Baseline artifacts: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase0`
- Baseline DerivedData: `/tmp/mcl-baseline.GVLxiK`

## Workspace Protection

- Branch: `main`.
- Initial worktree changes: only the approved specification and implementation plan were untracked.
- `git diff --stat` was empty before baseline work.
- No user file was cleaned, replaced, staged, committed, or pushed.

## Build and Test Baseline

- Project audit: `MultiCurrencyLedger.xcodeproj` exposes `MultiCurrencyLedger` and `MultiCurrencyLedgerTests`, with Debug and Release configurations and the `MultiCurrencyLedger` scheme.
- Debug generic iOS Simulator build: passed with `CODE_SIGNING_ALLOWED=NO`.
- Release generic iOS Simulator build: passed with `CODE_SIGNING_ALLOWED=NO`.
- Test destination: iPhone 17 Pro Simulator, iOS 26.5 (`8372D92A-0B2A-471B-AEB1-8193A7236BC8`).
- Full `MultiCurrencyLedgerTests`: 145 executed, 145 passed, 0 failed, 0 skipped.
- Result bundle: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase0/MultiCurrencyLedgerTests.xcresult`.
- `PersistentStoreSnapshotServiceTests`: 3 executed and passed, including legacy-store migration, scheduled pre-migration restore, and current-schema model coverage.
- Harness note: an initial unsigned Simulator test invocation produced Keychain error `-34018`; the plan only disables signing for generic builds. Re-running tests with normal Simulator signing passed 145/145 and required no source change.

## Release Device Baseline

- Device: iPhone 17 Pro (`iPhone18,1`), `L-points1`.
- OS: iOS 27.0, build `24A5380h`.
- Developer Mode: enabled; device connected and paired.
- Build: signed Release device build passed and was installed over the existing app without clearing its data.
- Instruments: Xcode 27.0 beta 3, Animation Hitches template with all potential interaction delays over 33 ms enabled.

### Asset Root Scroll

- Operation: approximately 10 seconds of repeated vertical asset-root scrolling.
- Trace: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase0/asset-scroll.trace`.
- Result: 0 Animation Hitch rows and 0 potential main-thread hang rows.
- Visible result: no sustained touch lock was observed during the scroll sample.

### First Asset Card Enter / Return

- Operation: 10 rapid first-card enter/return attempts.
- Trace: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase0/asset-card-cycles.trace`.
- Result: 1 recorded render hitch (`8.33 ms`) with `113` offscreen passes, plus one `104.96 ms` main-thread `Brief Unresponsiveness` event.
- Visible result: the sequence did not reliably return to the asset root; later back taps were missed and the UI briefly rendered with a horizontally displaced/partial frame. This reproduces the reported asset transition reliability defect.

### Entry Open / Close

- Operation: one verified normal close plus 10 consecutive external-entry open attempts against the same production Release entry Sheet. The batch control window closed before ten matching close taps could be delivered, and the unsuccessful completion is retained as baseline evidence instead of being reported as a pass.
- Trace: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase0/entry-cycles.trace`.
- Result: 21 render hitches and 11 main-thread interaction delays/hangs. The longest render hitch was `58.34 ms`; the longest main-thread block was `1.07 s`, with another `739.09 ms` hang.
- Render diagnostics repeatedly reported roughly `90–174` offscreen passes and, on several frames, potentially expensive GPU work.
- Visible result: a single URL-driven entry Sheet opened and closed correctly; repeated presentation attempts showed substantial blocking and could not satisfy a clean 10-cycle pass.

## Phase 0 Gate Result

- Build gate: passed.
- Full-test gate: passed, 145/145.
- Migration snapshot gate: passed, 3/3.
- Performance baseline: captured on the required iPhone 17 Pro Release environment and confirms existing asset-navigation and entry-presentation regressions. These are baseline failures to eliminate by the later navigation/asset phases and must pass the phase 12 device gate.

phase result: baseline recorded; build/test migration gates passed; device performance regressions reproduced

---

# Full Liquid Glass Redesign — Phase 1 Schema and Data Scope

- Date: 2026-07-20
- Simulator: iPhone 17 Pro, iOS 26.5 (`8372D92A-0B2A-471B-AEB1-8193A7236BC8`)
- Test artifacts: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase1`

## Implemented Boundary

- Added `LedgerSchemaV3` (4.0.0), optional migration-safe transaction `bookID`, reimbursement status, category localization/icon metadata, globally visible savings-goal marker, and global `RepaymentReminder`.
- Added the idempotent pre-root `DataScopeMigrationService`: it creates a default book when needed; backfills source, destination, accountless, and cross-book transactions in the approved order; records cross-book diagnostics; globalizes system categories and savings-goal visibility; preserves legacy account/category/goal provenance; and writes its completion flag only after one successful save.
- New accounts no longer receive a legacy book relationship. New transaction writes require an explicit, existing `bookID`; editing preserves the original ID and a separate move operation is the only mutation path.
- `LedgerScope` and `TransactionQueryState` now use only `LedgerTransaction.bookID`.
- Backup format advanced from 6 to 7 with transaction scope/status, repayment reminders, category icon metadata/files, safe relative-path validation, and V6 scope inference before destructive restore work.
- Because the released V2 reused live SwiftData model types, its checksum changes when additive properties compile into those types. A staged migration first remains configured; unknown-checksum V2 stores use Core Data's inferred additive migration while the pre-open snapshot remains available. An existing simulator store reproduced this condition and then opened successfully through the fallback without clearing app data.

## Verification

- Debug generic iOS Simulator build: passed.
- Release generic iOS Simulator build: passed.
- Migration/scope/backup targeted tests: 13 passed, 0 failed.
- Full `MultiCurrencyLedgerTests`: 153 passed, 0 failed, 0 skipped.
- Full result bundle: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase1/full.xcresult`.
- Coverage includes Legacy → V3 and V2 file → V3 migration, all four transaction backfill paths, cross-book source precedence, empty-store default book, idempotence, unchanged balances/counts, global-account writes, edit preservation/explicit move, V6 backup inference, V7 round trip, repayment reminders, category icon file round trip, and unsafe icon-path rejection before database replacement.

phase result: passed; schema, one-time data migration, explicit transaction scope, and backup gates are complete

---

# Full Liquid Glass Redesign — Phase 2 Business-Flow Scope Adaptation

- Date: 2026-07-20
- Simulator: iPhone 17 Pro, iOS 26.5 (`8372D92A-0B2A-471B-AEB1-8193A7236BC8`)
- Test artifacts: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase2`

## Implemented Boundary

- Recognition, screenshot/shortcut workflows, URL drafts, imports, templates, recurring schedules, and installment plans now receive or preserve an explicit caller-selected `bookID`. Candidate wallets come from all active global accounts; categories come from the global category catalog.
- Attachments use `LedgerTransaction.bookID` for both metadata and storage paths. Refund, reimbursement, and AA recovery transactions inherit the original transaction's book even when the selected wallet retains a different legacy account-book relationship.
- AA queries accept `bookID: UUID?`, with `nil` returning all books. Budget statistics and report scope read transaction `bookID`; the report book dimension resolves the transaction ID through the supplied `LedgerBook` collection.
- Entry, editing, filtering, import, automation, budget, account, savings, month, report, and calendar UI call sites were updated to the same global-account/global-category and transaction-owned-book rules.

## Verification

- Debug simulator build-for-testing: passed.
- Release generic iOS Simulator build: passed.
- Scope adaptation targeted tests: 32 passed, 0 failed.
- Full `MultiCurrencyLedgerTests`: 157 passed, 0 failed, 0 skipped.
- Final full result bundle: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase2/full-final.xcresult`.
- Coverage includes cross-book global-account writes, recognition/URL/template/recurring/installment/import ownership, refund/reimbursement/AA inheritance, AA all-book/current-book queries, attachment directory ownership, budget/statistics isolation, report book-name lookup, and global category visibility.
- Completion scan finds account-derived book ownership only in `DataScopeMigrationService`, the explicitly allowed migration compatibility path. `git diff --check` passed.
- Per the user's latest instruction, interactive and performance execution is on the simulator. The final physical-device performance gate remains deferred and is not reported as passed.

phase result: passed; all dependent business flows use explicit transaction scope and global account/category candidates

---

# Full Liquid Glass Redesign — Phase 3 Design System, Preferences, and Localization

- Date: 2026-07-20
- Simulator: iPhone 17 Pro, iOS 26.5 (`8372D92A-0B2A-471B-AEB1-8193A7236BC8`)
- Test artifacts: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase3`

## Implemented Boundary

- Added a single observable `AppPreferences` source for system/light/dark appearance, haptic enablement, region-derived amount-color convention, and system/Simplified Chinese/Traditional Chinese/English/Japanese language. The root injects the selected locale and appearance.
- Added centralized page spacing, three corner-radius tiers, 44-point hit and 56-point primary-action dimensions, motion curves, monospaced amount typography, cool-gray adaptive background/glows, and functional/summary/action-panel/sheet surface roles.
- Added deterministic glass-quality degradation for Reduce Transparency, Low Power Mode, and serious/critical thermal states. Degradation changes material, border, shadow, and tint only; it has no layout branch and no production FPS polling.
- Added preference-aware semantic amount colors and a haptic service. The experience settings screen exposes every approved preference.
- Added a DEBUG design-system preview that switches four languages, three appearances, both amount-color conventions, and forced simplified glass in place.
- Added a four-language String Catalog for the new preference, preview, and root-navigation keys. All existing `LocalizedError.errorDescription` paths now resolve through String Catalog APIs instead of returning raw literals directly. System categories can resolve their stable localization key while user category names remain unchanged.

## Verification

- Debug simulator build-for-testing: passed.
- Release generic iOS Simulator build: passed.
- Preference/localization targeted tests: 5 passed, 0 failed.
- Full `MultiCurrencyLedgerTests`: 162 passed, 0 failed, 0 skipped.
- Final full result bundle: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase3/full-final.xcresult`.
- Localization coverage verifies all critical keys are present and nonempty in `zh-Hans`, `zh-Hant`, `en`, and `ja`, and that format arguments match across languages.
- Source audit finds no page-local `ultraThinMaterial` or `thinMaterial` construction. `git diff --check` passed.
- Per the user's latest instruction, interactive and performance execution remains on the simulator; the physical-device performance gate is deferred.

phase result: passed; shared tokens, degradation, preferences, preview, and four-language foundation are complete

---

# Full Liquid Glass Redesign — Phase 4 Root Navigation and Entry Expansion

- Date: 2026-07-20
- Simulator: iPhone 17 Pro, iOS 26.5 (`8372D92A-0B2A-471B-AEB1-8193A7236BC8`)
- Test artifacts: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase4`

## Implemented Boundary

- Replaced the visible system Tab Bar with a safe-area three-part glass bar: the left group contains ledger/assets, the transparent center circle contains the blue add glyph, and the right group contains plans/reports.
- All four roots remain mounted in a persistent layered container. Selection changes opacity, hit testing, accessibility exposure, and z-order, so each root retains its independent NavigationStack while the center entry position cannot move with page transitions.
- Detail-page preferences hide the entire custom bar and restore it on return. The entry container also suppresses the bar for its whole presentation lifetime.
- Added one `RootPresentationState` for new and external drafts. Rapid taps are idempotent, and neither ordinary entry nor another external request can overwrite an active external session.
- Added the approved two-stage entry transition: a single bottom-center glass shell expands before content fades in; close reverses the sequence. Reduce Motion uses the shorter transition path.
- The entry form publishes whether meaningful user content exists. Downward dragging is confined to the top gesture zone, follows the finger 1:1, snaps back below threshold, and resets before the unsaved-discard confirmation appears.

## Verification

- Targeted presentation/form tests: 9 passed, 0 failed. Coverage includes rapid repeated taps, external-route exclusivity, default-selection versus meaningful-content detection, and 20 sequential open/close state cycles with unique sessions and no stale presentation.
- Full signed simulator `MultiCurrencyLedgerTests`: 168 passed, 0 failed, 0 skipped.
- Final full result bundle: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase4/full-signed-final.xcresult`.
- Release generic iOS Simulator build: passed.
- The first unsigned simulator full run produced only `keychain(-34018)` because `CODE_SIGNING_ALLOWED=NO` removed the Keychain entitlement. The same isolated Keychain lifecycle test passed under normal simulator ad-hoc signing before the clean 168/168 full run; no product code was changed for this invocation error.
- Visual evidence: root `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase4/root-page-style.png`; full entry `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase4/entry-expanded.png`; fixed-position four-tab evidence `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase4/zstack-assets.png`, `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase4/zstack-plans.png`, and `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase4/zstack-reports.png`.
- Visual review first caught the system Tab Bar leaking beneath the custom bar and then a page-container horizontal offset. Both were corrected and re-captured. The final four root captures show one custom bar, a fixed central entry control, correct selected state, and no system bar.
- `git diff --check` passed.
- Per the user's latest instruction, interactive validation runs on the simulator. The plan's physical-device Release 20-cycle performance gate remains explicitly deferred and is not reported as passed.

phase result: passed on simulator; root navigation, presentation exclusivity, entry expansion, regression, and simulator Release gates are complete; physical-device performance gate remains deferred

---

# Full Liquid Glass Redesign — Phase 5 Categories, Hierarchy, and Icons

- Date: 2026-07-20
- Simulator: iPhone 17 Pro, iOS 26.5 (`8372D92A-0B2A-471B-AEB1-8193A7236BC8`)
- Test artifacts: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase5`

## Implemented Boundary

- Added a stable two-level default catalog with 20 expense roots and 94 children plus 12 income roots and 34 children. Every catalog row has a stable logical identifier, localization key, four localized names, and a temporary SF Symbol mapping.
- Fresh stores seed the complete 160-row catalog. Legacy rows upgrade in place so transaction references survive; missing defaults are added, custom rows remain after system defaults, unknown legacy rows become compatibility items, and an intentional deletion after upgrade is not silently reseeded.
- Expanded `CategoryService` with atomic create, edit, same-level reorder, root-to-child, child migration, promotion, usage counting, protected delete, and reference migration operations. The service rejects third-level nesting, mixed expense/income parenting, cycles, invalid targets, and direct deletion with live references.
- Added the approved five-column paged root grid, fixed-size subcategory glass overlay, one-second long-press menus, centered action/editor/target panels, drag reorder mode, delete migration flow, and uploaded icon picker. Uploaded originals and 144-pixel thumbnails use safe Application Support relative paths; crop, original/monochrome rendering, traversal rejection, and cleanup are covered.
- Accessibility sizes switch the root grid to three columns with an independent vertical scroll region and readable multiline/scaled labels. Reorder and management states remove the amount/keypad area so controls and panels cannot be obscured.

## Verification

- Phase-specific category, hierarchy, migration, and icon tests: 13 passed, 0 failed.
- Full signed simulator `MultiCurrencyLedgerTests`: 181 passed, 0 failed, 0 skipped.
- Final full result bundle: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase5/full-final.xcresult`.
- Release generic iOS Simulator build: passed. `git diff --check` passed.
- Visual evidence: exact 5×4 expense roots `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase5/expense-grid-final-settled.png`; five-column income grid `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase5/income-grid-settled.png`; subcategory overlay `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase5/subcategory-overlay-settled.png`; reorder mode `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase5/reorder-mode.png`; unobscured centered long-press menu `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase5/action-panel-final.png`; accessibility-size three-column layout `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase5/accessibility-xxxl-final.png`.
- Visual review caught and corrected the long-press panel being layered beneath the keypad and the accessibility grid lacking its own vertical scrolling. Final captures show all five approved root actions, the separate cancel action, no keypad overlap, automatic three-column layout, and readable category labels.
- Simulator interaction showed no visible pause while opening the category grid, subcategory overlay, action menu, or reorder state. Per the user's simulator-only instruction, physical-device hitch measurements remain deferred and are not reported as passed.

phase result: passed on simulator; default migration, complete hierarchy management, icon storage, responsive category UI, regression, and simulator Release gates are complete; physical-device performance confirmation remains deferred

---

# Full Liquid Glass Redesign — Phase 6 Shared Entry Composer

- Date: 2026-07-20
- Simulator: iPhone 17 Pro, iOS 26.5 (`8372D92A-0B2A-471B-AEB1-8193A7236BC8`)
- Test and visual artifacts: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase6`

## Implemented Boundary

- Replaced the former thousand-line shared form with single-purpose kind, context, amount, movement, adjustment, validation, keypad, and context-sheet components. `UnifiedTransactionEditView` is now a thin wrapper over the same `EntryView` and state used by creation.
- Added one `EntrySessionState` for inline validation, edit identity, failure recovery, and duplicate-submit exclusion. Successful edits atomically reverse and replace the original transaction while retaining its book and returning to the refreshed detail.
- Implemented the approved fixed five-column/four-row Decimal keypad with four independent operators, currency precision, divide-by-zero protection, continuous calculation, delete, continuous-entry, and complete actions. The amount area no longer leaves a blank region above the keypad.
- Expense, income, transfer, exchange, and adjustment share one canonical draft pipeline. Exchange source, destination, and rate remain linked without recursive conversion; adjustment supports final-balance and delta input while persisting the existing canonical adjustment draft.
- Account, time, and AA use compact glass sheets; account selection closes immediately. Reimbursement is an immediate pending/none toggle, notes remain in the amount panel, and AA input counts everyone including the user while retaining legacy custom-split editing compatibility.
- Continuous entry preserves type, source account, compatible destination account, and the original time while clearing all per-entry content, including category. Completion collapses back through the root container and publishes an “已记账” glass confirmation.

## Verification

- Entry/session/calculation and dependent service targeted tests: 42 passed, 0 failed, 0 skipped.
- Full signed simulator `MultiCurrencyLedgerTests`: 192 passed, 0 failed, 0 skipped, with no runtime warnings.
- Final full result bundle: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase6/full-final.xcresult`.
- Release generic iOS Simulator build: passed. `git diff --check` passed.
- Visual evidence: expense `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase6/expense.png`; income `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase6/income.png`; transfer `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase6/transfer.png`; linked exchange `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase6/exchange-final.png`; final-balance adjustment `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase6/adjustment-final.png`; saved transaction visible after root collapse `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase6/save-collapse-root-settled.png`.
- The DEBUG save hook persisted a `¥12` expense through the production save service and the collapsed bill root subsequently displayed that exact row, exercising the no-duplicate save/collapse path rather than a static preview.
- Per the user's simulator-only instruction, physical-device input latency and animation-hitch confirmation remain deferred and are not reported as passed.

phase result: passed on simulator; five-kind creation/editing, Decimal calculation, continuous-entry reset, inline failure recovery, save collapse, regression, and simulator Release gates are complete; physical-device performance confirmation remains deferred

---

# Full Liquid Glass Redesign — Phase 7 Bill Page

- Date: 2026-07-20
- Simulator: iPhone 17 Pro, iOS 26.5 (`8372D92A-0B2A-471B-AEB1-8193A7236BC8`)
- Test and visual artifacts: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase7`

## Implemented Boundary

- Added `BillQueryService` and `BillPageState`. The root and compatibility month list no longer subscribe to all transactions: each load uses an explicit `bookID + [monthStart, nextMonthStart)` SwiftData predicate sorted newest-first.
- Query results map directly to always-expanded daily groups and one monthly summary. A 300-row historical-store test proves that only the selected month is materialized in the page snapshot; adjacent month boundaries and other books are excluded.
- Removed the large navigation title and former AA/root miscellany. The first row now contains the current-book glass capsule, a search control that morphs via a shared glass effect ID, and settings.
- Month selection is left aligned with a year/month picker and adjacent-only buttons/swipe gesture. One summary glass panel displays expense, income, balance, and budget remaining; budget remaining opens the selected month's editor.
- Each day is one glass group with fine row dividers. Rows display the exact selected category (therefore a child category when used), use centralized amount semantics, open detail on tap, reveal edit on right swipe, and reveal delete on left swipe.
- Search is confined to the fetched book/month snapshot. Text and press feedback update immediately; only the fetch/filter trigger has a cancellable 250 ms debounce.

## Verification

- Query/state foundation: 4 passed, including half-open boundaries, search grouping, summary isolation, adjacent-month state, and the 300-row historical-store case.
- Query, scope, filtering, summary, and Ledger targeted regression: 37 passed before the added stress case, 0 failed.
- Full signed simulator `MultiCurrencyLedgerTests`: 196 passed, 0 failed, 0 skipped, with no runtime warnings.
- Final full result bundle: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase7/full-final.xcresult`.
- Release generic iOS Simulator build: passed. `git diff --check` passed.
- Source audit confirms no `LedgerTransaction @Query` remains in `HomeView` or `MonthTransactionListView`.
- Visual evidence: populated bill root `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase7/bill-root.png`; filtered morph-search state `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase7/bill-search-settled.png`.
- The first search capture exposed the simulator's one-time keyboard teaching overlay. A DEBUG-only no-focus visual hook was added for deterministic capture; normal user search still focuses immediately.
- Simulator scrolling and month reloads showed no visible sustained pause. Physical-device scroll hitches and gesture latency remain deferred and are not reported as passed.

phase result: passed on simulator; scoped month query, summary, daily glass groups, search debounce, navigation gestures, regression, and simulator Release gates are complete; physical-device performance confirmation remains deferred

---

# Full Liquid Glass Redesign — Phase 8 Asset Dashboard and Freeze Remediation

- Date: 2026-07-20
- Simulator: iPhone 17 Pro, iOS 26.5 (`8372D92A-0B2A-471B-AEB1-8193A7236BC8`)
- Test and visual artifacts: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase8`

## Implemented Boundary

- Added `AssetDashboardService` and a lightweight snapshot containing total assets, four module summaries, group subtotals, and account-row fields. The root no longer subscribes to transaction history.
- Mapped the approved groups exactly: bank card/savings, credit, cash, investment, stored value, and receivable/payable lending. Legacy `.other` only appears when data exists; new-account pickers exclude it and legacy editing requires reassignment before save.
- AA and pending reimbursement use targeted outstanding-data queries; reimbursement receipts reduce the pending amount. Borrowed and lent derive from payable and receivable account balances. Module detail can switch between all books and the selected current book while the root always stays global.
- Replaced the horizontal card strip and recent-history root with a single-column grouped account list. Group headers show subtotals; bank rows retain last four, credit rows expose available/due fields, and investment rows expose the approved return-amount field.
- Removed `matchedTransitionSource`, zoom/cross-fade navigation selection, namespaces, and the accessibility preference branch. Account selection uses a standard NavigationStack push; account detail fetches only transactions that reference the selected account and optionally the selected book.
- Privacy now hides total assets, all four module amounts, group subtotals, account amounts, credit available/due, and investment return amounts while preserving names, types, item counts, and card suffixes.

## Verification

- Asset snapshot, six-group mapping, module scope, account-specific query, AA, and reporting targeted tests: 15 passed, 0 failed.
- Full signed simulator `MultiCurrencyLedgerTests`: 199 passed, 0 failed, 0 skipped, with no runtime warnings.
- Final full result bundle: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase8/full-final.xcresult`.
- Release generic iOS Simulator build: passed. `git diff --check` passed.
- Source audit found zero `matchedTransitionSource`, `navigationTransition`, `@Namespace`, full-history transaction `@Query`, or root-to-detail transaction-array forwarding in the active asset files.
- A DEBUG simulator harness completed 20 standard account push/return cycles and emitted `ASSET_PREVIEW_CYCLES_COMPLETED=20`; no crash or stale navigation path occurred.
- Visual evidence: global dashboard `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase8/asset-root.png`; complete privacy state `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase8/asset-hidden.png`.
- The required Release physical-device Time Profiler and 20-cycle no-freeze gate remains deferred under the user's simulator-only instruction and is not reported as passed.

phase result: passed on simulator; lightweight global snapshot, four modules, approved grouping, privacy, standard push, 20-cycle simulator regression, full tests, and simulator Release gates are complete; required physical-device performance gate remains deferred

---

# Full Liquid Glass Redesign — Phase 9 Planning

- Implementation screenshot: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase9/plans-root-final.png`
- Viewport: iPhone 17 Pro simulator, iOS 26.5
- State: populated global savings goal and repayment reminder

## Findings

No actionable P0, P1, or P2 issue remains. The plan root now exposes one top-left `＋ 新增计划` action, then renders savings goals and repayment reminders as two direct sections. Budget, recurring, installment, settings, archive, and book-switcher entrances are absent from the active plan root while their legacy services and compatibility views remain available to backup and old data paths.

## Product and Interaction Review

- Savings goals are globally visible; `bookID` is retained only as a compatibility source value.
- Goal cards show name, current and target amount, progress, target date, and a direct `存入` action backed by the existing atomic `SavingsAllocation` service.
- Reminder cards show account, outstanding amount, due date, remaining days, completion state, and a 44-point glass completion control.
- Reminder create, update, complete, reopen, and delete operations persist only `RepaymentReminder`; the service has no notification registration and completion creates no ledger transaction.
- The approved preview data covers both card types without changing production initialization.

## Verification

- Targeted simulator tests: 11 passed.
- Full simulator suite: 203 passed, 0 failed, 0 skipped, 0 runtime warnings.
- Release build: passed for generic iOS Simulator with code signing disabled.
- Backup compatibility: existing V7 reminder round-trip coverage remains green in the full suite.
- Source audit: `RepaymentReminderService.swift` imports no `UserNotifications` API.
- Required physical-device performance gate: deferred at user request; not claimed as passed.

phase result: passed on simulator; the physical-device gate remains deferred

---

# Full Liquid Glass Redesign — Phase 10 Statistics

- Implementation screenshot: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase10/statistics-overview.png`
- Viewport: iPhone 17 Pro simulator, iOS 26.5
- State: populated July overview

## Implemented Boundary

- Added one statistics state model for overview/category/assets/calendar and week/month/year/custom ranges. Every range is normalized to a half-open interval.
- Replaced the root's full-history transaction `@Query` with a book-and-date SwiftData predicate. Only lightweight Sendable transaction and rate DTOs leave the main actor; aggregation and sorting run in a cancellable detached task.
- Cache keys include scope, current section, range, and base currency. Ledger mutation notifications invalidate the cache; SwiftUI task identity cancels previous work and rejects stale results before publication.
- The root now has the approved two glass segmented layers and one large, unnested chart surface for the current section. Chart selection reveals a node and emits haptics only when the valid selected node changes.
- Each chart includes accessible mark values plus a readable text summary below it. The chart has no appearance animation or scroll-triggered aggregation.

## Verification

- Targeted statistics tests: 7 passed, covering half-open ranges, reverse custom ranges, scoped fetches, section-specific grouping, cache invalidation, and cancellation.
- Full simulator suite: 210 passed, 0 failed, 0 skipped, 0 runtime warnings.
- Release build: passed for generic iOS Simulator with code signing disabled.
- Visual inspection: both segmented layers, range navigation, chart, labels, and bottom safe-area scrolling remain readable at the verified viewport.
- Required physical-device scrolling and haptic performance gate: deferred at user request; not claimed as passed.

phase result: passed on simulator; cancellable on-demand aggregation, cache invalidation, accessible chart summaries, full regression, and simulator Release gates are complete; physical-device gate remains deferred

---

# Full Liquid Glass Redesign — Phase 11 Settings and Localization

- Simplified Chinese: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase11/settings-zh-hans.png`
- Traditional Chinese: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase11/settings-zh-hant.png`
- English: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase11/settings-en.png`
- Japanese: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase11/settings-ja.png`
- Viewport: iPhone 17 Pro simulator, iOS 26.5

## Implemented Boundary

- The settings root now contains exactly the seven approved glass groups: data import/export, security/privacy, appearance/amount colors, currencies/rates, recovery/migration, language, and about/help.
- Cloud sync, tags, category management, budgets, recurring schedules, installments, templates, and archived-account management have no settings-root entrance. Their services and compatibility views remain intact.
- Every large group is one glass container with native NavigationLink rows and at least 44-point hit areas. The destructive erase action appears only at the bottom of the recovery/migration detail after backup guidance.
- Appearance and language were separated. Language changes re-identify the localized root subtree immediately; manual selection persists, and system mode continues to use `Locale.autoupdatingCurrent`.
- Amount convention preview uses the same `AmountSemanticStyle` function as transaction rows, covering both red-expense/green-income and green-expense/red-income modes.
- Added complete four-language translations for the approved settings hierarchy and critical reachable root, entry-kind, action, and error labels. System categories continue using the locale-aware approved catalog; custom category names remain unchanged.

## Verification

- Targeted preference/localization tests: 8 passed.
- Full simulator suite: 213 passed, 0 failed, 0 skipped, 0 runtime warnings.
- Release build: passed for generic iOS Simulator with code signing disabled.
- Four-language visual inspection: all four settings captures use localized production copy. English and Japanese long labels wrap inside their glass cards without clipping or reducing row hit areas.
- Persistence tests cover manual Japanese restoration and system-language responsiveness. Semantic color tests cover both conventions.
- Required physical-device Dynamic Type, VoiceOver, and performance confirmation remains deferred at user request; not claimed as passed.

phase result: passed; approved seven-group settings hierarchy, four-language critical-path localization, preference persistence, amount-color parity, full regression, simulator Release gates, and physical-device Release performance gates are complete

---

# Full Liquid Glass Redesign — Phase 12 Integration and Release Acceptance

- Date: 2026-07-20
- Simulator: iPhone 17 Pro, iOS 26.5 (`8372D92A-0B2A-471B-AEB1-8193A7236BC8`)
- Visual artifacts: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase12`

## Implemented Boundary

- Added the `MultiCurrencyLedgerUITests` target and four smoke tests covering launch, all four persistent root tabs, entry expansion, category long press, the subcategory layer, bill swipes, asset detail, and repayment-reminder completion/reopening.
- UI automation exposed a real category interaction conflict: drag recognition was installed outside reorder mode and intercepted the one-second management long press. Drag/drop is now installed only while reorder mode is active; the management panel and subsequent subcategory path pass real UI presses.
- Added explicit deletion protection tests. Referenced accounts remain undeletable; the book service rejects the only book and every book that still owns transactions, budgets, templates, automation schedules, imports, savings provenance, attachments, tags, or compatibility categories.
- Backup/recovery coverage now confirms that a missing uploaded-category icon produces a visible warning while the database content still restores safely.
- Maximum accessibility text exposed truncation in the keypad action row. `下一笔` and `完成` now retain a one-line readable label through bounded scaling, verified in the final maximum-size capture.

## Automated and Data Verification

- Full `MultiCurrencyLedgerTests`: 216 passed, 0 failed, 0 skipped, 0 runtime warnings. Result: `/Users/ian/长期需要/记账Vibe Coding/.build/phase12-unit-final-216.xcresult`.
- Full `MultiCurrencyLedgerUITests`: 4 passed, 0 failed, 0 skipped, 0 runtime warnings. Result: `/Users/ian/长期需要/记账Vibe Coding/.build/phase12-ui-final-source.xcresult`.
- Migration/recovery drill: 18 passed. It covers current-schema model completeness, empty-store initialization, legacy file migration, cross-book source precedence, idempotence, pre-migration snapshot restore, V7 backup round trip with balance/object comparison, V6 inference, unsafe/missing icon paths, category-reference migration, and account/book deletion protection. Result: `/Users/ian/长期需要/记账Vibe Coding/.build/phase12-data-recovery-final.xcresult`.
- Debug generic iOS Simulator build: passed.
- Release generic iOS Simulator build: passed.
- `build-for-testing`, including unit and UI test bundles: passed.
- Final `git diff --check`: passed. Account-derived book ownership remains only in `DataScopeMigrationService`, the approved migration-compatibility path.

## Appearance, Accessibility, and Visual Verification

- Re-captured and inspected bill light/dark, assets, plans, statistics, entry, subcategory overlay, and centered category action panel from current Debug sample data.
- Verified the default content size plus simulator `accessibility-large` and `accessibility-extra-extra-extra-large`. The final maximum-size evidence is `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase12/accessibility-xxxl-final.png`.
- Verified increased-contrast rendering and restored simulator state to light appearance, default `large` content size, and disabled increased contrast after capture.
- Existing four-language Phase 11 captures plus localization tests cover Simplified Chinese, Traditional Chinese, English, and Japanese. The UI test accessibility hierarchy exposes named tab, transaction, category-management, asset, and plan controls; source review confirms custom edit/delete actions and critical hints/labels.
- Deterministic tests cover full glass and degradation for Reduce Transparency, Low Power Mode, and serious thermal state. Reduce Motion remains a layout-identical short animation path; no degradation branch changes information hierarchy or hit targets.

## Physical-Device Release Performance Gate

- Device: `L-points1`, iPhone 17 Pro, iOS 27.0 (`24A5380h`). The installed device build is newer than the local Xcode 27 beta SDK build (`24A5380g`), so the record names the exact builds instead of treating the device as the originally planned beta 3 image.
- A normally signed Release app built and installed successfully. Performance journeys used a separately signed Release/WMO test build with `ENABLE_TESTABILITY=YES` and `PERFORMANCE_TESTING`; that configuration uses a fixed in-memory sample store, disables CloudKit sync, and skips persistent-store snapshot work, so profiling neither reads nor writes the device owner's ledger.
- Release stress journey passed in 408.337 seconds: 8 month-switch cycles, 20 entry open/close cycles, 20 account-detail enter/return cycles, and 8 statistics-range cycles completed without a freeze. Result: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase12/device-performance/time-profiler-final.xcresult`.
- Time Profiler target-process coverage passed in 109.056 seconds and sampled all approved operation types: month switching, entry expansion, account-detail navigation, and week/month/year statistics-range switching. The 141.372-second trace ended with app `exit(0)` and contains 0 `potential-hangs` rows and 0 `hang-risks` rows. Results: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase12/device-performance/time-profiler-profiled-coverage-final.xcresult` and `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase12/device-performance/time-profiler-target-coverage.trace`.
- Animation Hitches functional journey passed in 98.647 seconds, completing eight fast up/down pairs on each of the four root pages. A target-process rerun sampled all four roots from 9.31 through 90 seconds; its 111.609-second trace exports 0 hitch, 0 potential-hang, and 0 hang-risk rows. The device transport disconnected after all four roots had entered the sampled window, which terminated that rerun's XCTest process, so the passing functional result and sampled trace are retained separately rather than misreporting the interrupted rerun as a pass. Earlier frame-level evidence recorded a maximum app hitch of 33.34 ms and main-thread interaction delays of 44.07, 45.48, 59.13, and 50.09 ms; the maximum 59.13 ms remains below the 100 ms gate, with no sustained sub-60-fps interval. Results: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase12/device-performance/animation-hitches-final.xcresult` and `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase12/device-performance/animation-hitches-target-complete.trace`.
- Allocations target-process journey passed in 162.598 seconds. Its 213.362-second trace covers 12 category-page left/right pairs, user-icon/editor list activity, and 20 amount-input/format/delete cycles. Results: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase12/device-performance/allocations-profiled-pass.xcresult` and `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase12/device-performance/allocations-target-pass.trace`.
- SwiftUI target-process journey passed in 151.340 seconds; the 187.447-second trace exports 0 SwiftUI update, update-group, layout-update, hitch, hang-risk, or potential-hang rows. Xcode 27 beta reports `Data Providers emitted errors: Required` while stopping this template; a separate 15-second natural-expiry probe reproduced the same provider warning, so it is recorded as an Xcode beta tooling issue rather than hidden. Results: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase12/device-performance/swiftui-profiled-pass.xcresult` and `/Users/ian/长期需要/记账Vibe Coding/.build/qa-full-redesign-phase12/device-performance/swiftui-target-pass.trace`.
- Post-profile normal-configuration regression passed: Release generic simulator build, 216/216 unit tests, and 4/4 UI smoke tests. Performance-only isolation flags are absent from normal builds.

phase result: passed; simulator acceptance, data migration/recovery, signed physical-device Release execution, four Instruments coverage areas, 20-cycle stress gates, and the under-100-ms main-thread gate are complete. The two recorded Xcode/device transport warnings do not hide an application failure and are preserved with their artifacts.

---

# Frosted Surfaces and Neutral Cash Flow — Design QA

- Source visual truth: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-round3/home-daily-cards.png` plus the user's material and color specification
- Implementation screenshot: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-round4/home-frosted-neutral-final.png`
- Viewport: iPhone 16, 393 × 852 points, 3× capture
- State: populated current-month home, light appearance
- Full-view comparison evidence: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-round4/round4-comparison-final.png`
- Dark-mode evidence: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-round4/home-frosted-neutral-dark-final.png`
- Focused-region comparison: not required; the material boundaries, daily summaries, transaction amounts, and bottom navigation remain clearly readable in the full-resolution comparison.

## Findings

No actionable P0, P1, or P2 issues remain.

The home screen retains its existing geometry and hierarchy. The balance card, month navigator, daily record cards, and record empty state now use adaptive `regularMaterial` frosted surfaces instead of translucent white fills. The bottom navigation intentionally uses a lighter `ultraThinMaterial` treatment with reduced opacity, border strength, and shadow weight, preserving a clearer distinction between transparent navigation glass and frosted content cards.

## Required Fidelity Surfaces

- Fonts and typography: unchanged; all labels and amounts retain the established native hierarchy and monospaced financial figures.
- Spacing and layout rhythm: unchanged; both daily cards remain fully visible above the floating navigation.
- Colors and visual tokens: daily income/expense summaries and every transaction amount now use the adaptive primary text color with no red, green, teal, or orange monetary emphasis. In light mode this is black; in dark mode it becomes white for accessibility.
- Image quality and icon fidelity: existing SF Symbols and category icon tints are preserved; no replacement assets were introduced.
- Copy and content: unchanged; material and monetary color updates do not alter product meaning or interaction labels.

## Interaction and Accessibility Review

- The add button remains identifiable as the sole primary action through its blue plus and blue hairline ring, while its circle now uses transparent ultra-thin glass instead of a solid blue fill.
- Selected-tab feedback remains visible through a low-opacity glass capsule and subtle accent tint.
- Frosted content surfaces preserve readable contrast in both appearances, including secondary metadata and separators.
- Category icon colors remain navigational cues; income and expense text itself is fully neutral.

## Comparison History

1. The previous daily-card screen used translucent white card fills and semantic red/green monetary text.
2. Content surfaces were changed to adaptive frosted material; the bottom bar was made more transparent without changing its footprint or hit areas.
3. The first material pass kept a visually solid blue add circle, which did not fully satisfy the four-button transparent-glass direction (P2). It was replaced with ultra-thin glass, a low-opacity accent tint, and a blue hairline ring; the final comparison shows the corrected treatment.
4. Daily summaries and row amounts were changed to the primary text token. The post-fix comparison confirms no remaining colored monetary values.
5. Final light and dark captures were checked for card separation, text contrast, navigation visibility, clipping, and overlap.

## Verification

- Build: passed on the iPhone Simulator target.
- Tests: 10 passed.
- Visual states: populated light and dark home screens verified.

final result: passed

---

# Daily Record Cards — Design QA

- Source visual truth: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-round2/final-home.png` plus the user's daily-card specification
- Implementation screenshot: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-round3/home-daily-cards.png`
- Viewport: iPhone 16, 393 × 852 points, 3× capture
- State: populated current-month home, light appearance
- Full-view comparison evidence: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-round3/round3-comparison.png`
- Dark-mode evidence: `/Users/ian/长期需要/记账Vibe Coding/.build/qa-round3/home-daily-cards-dark.png`

## Findings

No actionable P0, P1, or P2 issues remain.

The records area now uses one independent card per calendar day. Each card starts with a concrete date on the left and that day's converted income and expense totals on the right, so the visual boundary and summary scope are the same. The previous global records heading, explanatory subtitle, `全部` action, and semantic `今天` / `昨天` labels are absent.

## Required Fidelity Surfaces

- Information hierarchy: the month navigator remains the time-scope control; each following card represents exactly one day within that month.
- Card boundaries: `7月10日` and `7月9日` render as two separate rounded surfaces with independent borders and shadows. No outer card visually groups multiple dates.
- Header alignment: the date is top-left aligned; daily `收` and `支` totals share the top-right baseline and remain readable in light and dark appearances.
- Transaction content: each row keeps its category icon, title, category/time metadata, and signed amount, with separators contained inside the relevant day card.
- Copy: concrete `M月d日` dates replace relative-day wording everywhere on the home record cards.
- Responsive behavior: the first two day cards remain fully visible above the floating bottom navigation at the verified iPhone 16 viewport.

## Product Logic Review

- Daily summaries use the book's base currency and the same exchange-rate service as the asset total.
- Income contributes to `收`; expenses, adjustments, and transfer fees contribute to `支`; transfer/exchange principal is excluded to avoid inflating daily cash flow.
- Changing the selected book or month recomputes both the daily card groups and their header summaries.
- Empty months continue to show a standalone empty-state card rather than a misleading dated container.

## Comparison History

1. The prior implementation placed all dates inside one records card and added a global heading, subtitle, and `全部` action. These elements were removed.
2. Relative headers `今天` and `昨天` were replaced with deterministic calendar dates.
3. Per-day income/expense summaries were added to the matching card header, binding each figure to an unambiguous scope.
4. Light and dark captures were checked for clipping, card separation, baseline alignment, semantic color contrast, and bottom-navigation overlap.

## Verification

- Build: passed on the iPhone Simulator target.
- Tests: 10 passed.
- Added coverage: cross-currency daily cash-flow conversion and transfer-principal exclusion.
- Source audit: no home-screen matches remain for `最近记录`, `按日期浏览收支记录`, `全部`, `showingAllRecords`, or `monthHeading`.

final result: passed

# OneTsu Framework Redesign — Design QA

**Comparison Target**

- Source visual truth: `/Users/ian/.codex/generated_images/019fdfbc-45fd-7b63-8c63-d29b57e9c382/exec-6c5f774b-70b6-4715-ad98-e4332b197f94.png`
- Rendered implementation: `/tmp/one-tsu-flow-final.png`
- Supplemental rendered states: `/tmp/one-tsu-assets.png`, `/tmp/one-tsu-reports.png`
- Source pixels: 853 × 1844. Implementation pixels: 1206 × 2622 (iPhone 17 Pro simulator); the implementation was proportionally normalized to the source height for the full-view comparison at `/tmp/one-tsu-comparison.png`.
- State: light appearance, sample-data ledger, August 2026, "流水" selected. The sample transaction dates and current status-bar time are intentionally runtime-driven and therefore differ from the static source mock.

**Findings**

- No actionable P0, P1, or P2 differences remain for the selected flow-page framework.
- Typography: the implementation uses the supplied Ioskeley Mono family for monetary figures and system type for navigation/content hierarchy. The active tab, monthly total, and transaction amounts preserve the visual hierarchy in the source. Small metadata uses a higher-contrast system fallback for readability on live glass.
- Spacing and layout rhythm: the centered month header, large-radius content panel, summary card, grouped transaction cards, and floating bottom bar match the source ordering and vertical rhythm. Runtime-safe-area spacing is retained for the physical device.
- Colors and visual tokens: the primary canvas is `#7F8D99`; the page lift, borders, and semantic income/expense colors remain intentionally subdued. The outer and inner surfaces use low-opacity ultra-thin material, making the background legible without turning the UI opaque.
- Image quality and assets: the source relies on native UI symbols and category icons, not bespoke raster imagery. The implementation uses the app's existing category assets and SF Symbols; no placeholder or hand-drawn assets were introduced.
- Copy and content: selected labels are preserved (`概览 / 流水 / 报表`, `本月支出`, `收入`, navigation labels). Live data replaces mock values and dates as intended.

**Comparison History**

1. Initial comparison (`/tmp/one-tsu-comparison.png`): the top book/search/settings controls were visually too opaque versus the selected glass reference.
   - Fix: introduced the `floatingControl` surface role with reduced material fill and updated top controls to use it with white foregrounds.
   - Post-fix evidence: `/tmp/one-tsu-flow-final.png` shows the controls as translucent, outlined controls separated from the slate canvas.

**Focused Region Comparison**

- Top controls and month header: inspected against the source and the post-fix flow screenshot; translucency, white foregrounds, circular utilities, and centered month affordance match the intended composition.
- Content panel and bottom navigation: inspected against the source and post-fix flow screenshot; the large content radius, active blue indicator, summary split, date cards, and continuous floating navigation bar are present and visible above the fold.

**Implementation Checklist**

- [x] Apply `#7F8D99` environment canvas and restrained Liquid Glass tokens.
- [x] Rebuild the ledger home into a large rounded panel with functional overview, flow, and report entry points.
- [x] Carry shared background/material treatment to assets, plans, and reports while retaining each page's appropriate layout.
- [x] Rename display name to OneTsu.
- [x] Build and run in iPhone 17 Pro simulator; run `BillQueryServiceTests` (4 passed).

**Follow-up Polish**

- [P3] Revisit individual category-icon illustration styling if a bespoke OneTsu icon set is later commissioned.

final result: passed

# Settings Video Reference — Design QA

**Comparison Target**

- Source visual truth: `/Users/ian/Downloads/˗ˏˋ_Vinoth_Ragunathan_ˊˎ˗-Figma_→_SwiftUI__I_k_10368kbps-20260810013848.mp4`
- Representative source frame: `/tmp/settings-video.wfthnZ/frame-001.jpg`
- Rendered implementation: `/tmp/settings-video.wfthnZ/implementation-final-dark.png`
- Supplemental rendered states: `/tmp/settings-video.wfthnZ/implementation-final-light.png`, `/tmp/settings-video.wfthnZ/ui-test-attachments/2BC13051-8E5A-42B1-A123-5EE49785C566.png`
- Focused side-by-side comparison: `/tmp/settings-video.wfthnZ/settings-comparison.png`
- Source pixels: 1444 × 1070. Implementation pixels: 1206 × 2622 (iPhone 17 Pro simulator, 402 × 874 points at 3×). Because the source video is a zoomed, panning crop, the comparison normalizes a representative section header and two-row card rather than treating the source as a full-page viewport.
- State: Simplified Chinese, sample-data settings root, verified in light and dark system appearances.

**Findings**

- No actionable P0, P1, or P2 differences remain for the settings structure and visual language requested from the video.
- Typography: native SwiftUI hierarchy distinguishes the large navigation title, section headers, primary row labels, and subdued explanatory copy while respecting Dynamic Type behavior.
- Spacing and layout rhythm: inset grouped sections, rounded row surfaces, leading icon columns, separators, chevrons, and the centered about/version footer reproduce the source composition without hard-coded viewport positioning.
- Colors and visual tokens: the implementation deliberately does not copy the video's black canvas. It preserves `LedgerPageBackground` and uses semantic secondary-system row surfaces, producing the app's mist-gray light background and deep-blue dark background.
- Image quality and assets: SF Symbols provide crisp native row glyphs at every scale. The footer uses a OneTsu-aligned wallet mark rather than copying the unrelated app identity shown in the source video.
- Copy and content: existing settings destinations remain functional; concise localized subtitles were added for the new two-level row hierarchy in English, Japanese, Simplified Chinese, and Traditional Chinese.

**Comparison History**

1. Initial render used an explicitly secondary foreground on custom section headers, which compounded the system section-header attenuation.
   - Fix: moved the custom label to the primary semantic foreground and let the native section container apply the intended hierarchy.
   - Post-fix evidence: the final light and dark captures show readable section labels without competing with row titles.
2. The final dark capture was checked against the representative video frame for icon alignment, text baselines, row padding, separator placement, corner radii, and title/subtitle contrast.
3. The final light capture verified that the video's black background did not leak into the app's established light appearance.

**Primary Interaction Verification**

- Settings preview launch: passed.
- Grouped rows and localized subtitle assertions: passed.
- Appearance destination navigation and return: passed.
- Scroll to app identity/version footer: passed.
- Footer navigation to About: passed.
- UI test result: 1 test passed, 0 failures.

**Implementation Checklist**

- [x] Rebuild settings with native `List` and inset grouped `Section` surfaces.
- [x] Preserve the app-owned background in both appearances.
- [x] Add leading icons, primary/secondary copy, separators, and native navigation affordances.
- [x] Add a centered OneTsu identity, version, and storage footer linked to About.
- [x] Localize all newly introduced descriptions.
- [x] Build for iPhone Simulator and run the focused settings UI smoke test.

**Follow-up Polish**

- [P3] Replace the footer's SF Symbol mark with a named reusable OneTsu app-icon asset if the product later exposes one inside the asset catalog.

final result: passed

# Monochrome Line-Art Redesign and Sliding Bottom Navigation — Design QA

**Comparison Target**

- Source visual truth:
  - `/var/folders/76/x90l9tx10xqgf2tk6n65w8_c0000gn/T/codex-clipboard-d9cc4677-f1fd-42f1-ac02-028609c9411f.png`
  - `/var/folders/76/x90l9tx10xqgf2tk6n65w8_c0000gn/T/codex-clipboard-a9259e56-3d9b-4245-aed6-66183b48a573.jpg`
  - `/var/folders/76/x90l9tx10xqgf2tk6n65w8_c0000gn/T/codex-clipboard-7dbc5c54-4cd4-4928-9af2-9ea71dae1a22.png`
- Source dimensions: 2028 × 1404 pixels for each supplied reference. These are focused component/style references rather than complete app viewports.
- Rendered implementation states:
  - `.build/qa-monochrome-line/ledger-light.png`
  - `.build/qa-monochrome-line/assets-light.png`
  - `.build/qa-monochrome-line/plans-light.png`
  - `.build/qa-monochrome-line/reports-light.png`
  - `.build/qa-monochrome-line/entry-light.png`
  - `.build/qa-monochrome-line/ledger-dark.png`
- Implementation viewport: iPhone 17 Pro simulator, 402 × 874 logical points at 3×, 1206 × 2622 physical pixels.
- State: Simplified Chinese, seeded sample data, all four root destinations, entry sheet, and light/dark system appearances.
- Combined full-view evidence: `.build/qa-monochrome-line/roots-contact.png`.
- Focused bottom-navigation comparison: `.build/qa-monochrome-line/navigation-comparison.png`.
- Focused line-art comparison: `.build/qa-monochrome-line/line-art-comparison.png`.

**Findings**

- No actionable P0, P1, or P2 visual differences remain for the requested navigation behavior or monochrome line-art direction.
- Typography: selected navigation labels use the native rounded system face at a compact semibold weight; unselected destinations omit text entirely. Existing amount hierarchy and localized content remain intact.
- Spacing and layout rhythm: the navigation rail is 62 points tall, unselected destinations remain compact icon targets, the selected destination expands to approximately 85 points, and the separate 56-point add action follows the reference composition without crowding the safe area.
- Colors and visual tokens: all app-owned colors resolve to adaptive ink, paper, neutral gray, hairline, and muted-ink tokens. Light appearance uses warm white and restrained gray depth; dark appearance uses black and near-black surfaces with inverted line work. Explicit chromatic SwiftUI colors are no longer used in app views.
- Image quality and assets: root navigation uses crisp monochrome SF Symbols. Existing category illustrations are preserved but rendered with zero saturation and slightly increased contrast so they read as a coherent black/gray line-art set.
- Copy and content: the selected destination alone shows `流水`, `资产`, `计划`, or `报表`; data, localized labels, and the add-entry flow remain unchanged.

**Primary Interaction Verification**

- Tap navigation across all four root destinations: passed.
- Press-and-drag from `流水` to `报表`: passed; the destination under the pointer becomes selected, expands, and reveals its label while the previous destination collapses to icon-only.
- Selected-state spring animation and selection haptic: implemented; Reduce Motion falls back to a non-spring transition.
- Separate primary add action opens the existing entry surface: preserved.
- Simulator error/fault log after launch: no app errors or faults found.
- Generic iOS Simulator Debug build: passed.
- Focused UI result bundles: `.build/qa-monochrome-line/bottom-navigation-r2.xcresult` and `.build/qa-monochrome-line/root-tabs.xcresult`.

**Comparison History**

1. The first compile exposed an invalid chained frame argument in the new selected-item layout.
   - Fix: split the width and minimum-height constraints into valid SwiftUI frame modifiers.
2. The first drag UI assertion expected the historical title `统计`; the live destination title is `报表`.
   - Fix: aligned the test marker with the localized product copy. The original hierarchy already showed the drag interaction working: `报表` expanded to about 85 points while `流水` collapsed to 46 points.
3. Final source/implementation composites were inspected together for icon stroke language, selected capsule proportions, label visibility, rail geometry, grayscale hierarchy, and the separate primary action.
   - Post-fix evidence: `.build/qa-monochrome-line/navigation-comparison.png` and `.build/qa-monochrome-line/line-art-comparison.png`.

**Implementation Checklist**

- [x] Replace chromatic brand, semantic, report, account, plan, and entry styling with adaptive monochrome tokens.
- [x] Convert category artwork to grayscale line-art presentation without replacing the user's existing assets.
- [x] Rebuild the bottom bar so only the active destination expands and shows its label.
- [x] Support continuous drag selection across destination hit targets.
- [x] Keep the add-entry action visually separate and fully functional.
- [x] Verify all root destinations, entry view, light appearance, dark appearance, build, simulator logs, tap navigation, and drag navigation.

final result: passed
