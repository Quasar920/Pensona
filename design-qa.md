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
