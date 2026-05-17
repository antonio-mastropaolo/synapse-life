# iOS Mobile Redesign — Integration Manifest

Branch: `worktree-ios-mobile-redesign`
Worktree: `/Users/amastro/Projects/Synnapse-worktrees/ios-mobile-redesign`

## Goal

Rebuild the iPhone experience as a real mobile product rather than a
macOS layout shrunk into a portrait viewport. The previous iOS shell was
structurally iOS-aware (a `TabView` existed, `iosLayout` branches
existed) but operationally still a macOS port: rows used fixed-pixel
column widths that overflowed iPhone width, the Finance tab rooted at
Personal instead of a hub, drill-down was missing, the Life tab kept its
navigation chrome rather than going full-bleed, and the Settings entry
was buried under a "More" tab.

## Cross-cutting concerns

These are the only surfaces that touch shared (non-iOS-only) code. All
other changes are scoped under `#if os(iOS)` blocks inside feature views
or live entirely in `apps/Synnapse-iOS/Features/`.

### 1. `LedgerFilter.swift` — new public reducers

Added two pure functions used by the iOS Transactions surface:

- `enum LedgerStatusScope: Sendable, Hashable, CaseIterable` with
  `apply(to:)` — backs the All / Pending / Posted segmented control.
- `groupTransactionsByCard(_:)` — groups a flat ledger by
  `accountName` (with fallbacks). Returns `[(card, rows)]`.

Both are public API on the `Features` module. No other agent touches
`LedgerFilter.swift`, but if Agent C (Transactions grouping) lands a
sibling reducer, the two should compose cleanly: scope first, then group.

### 2. `AppModel.financeAPI` is now exposed (iOS app target)

The iOS `AppModel` previously kept `FinanceAPI` private. The
`AccountDetailView` drill-down needs to spawn an account-scoped
`FinanceTransactionsViewModel`, so `financeAPI` is now a stored `let` on
the model. macOS app shell is untouched.

### 3. Snapshot baselines

Every iOS `.png` reference under `__Snapshots__/` was deleted by this
worktree. The corresponding tests are unchanged in shape; on the next
iOS-host run they will lazy-record fresh references that capture the new
layouts. macOS PNGs are untouched and continue to pass.

## What changed

### New files

- `apps/Synnapse-iOS/Features/FinanceHubView.swift` — 4-card Finance hub
  (Personal / Accounts / Transactions / Investments) with a net-worth
  strip on top. Owns the `NavigationStack`'s `.navigationDestination`
  entries for `FinanceAccount`, `Models.Transaction`, `InvestmentPosition`.
- `apps/Synnapse-iOS/Features/AccountDetailView.swift` — per-account
  drill-down: balance hero, available/limit metadata, recent activity
  tail scoped to the account via its own `FinanceTransactionsViewModel`.
- `apps/Synnapse-iOS/Features/TransactionDetailView.swift` — per-row
  drill-down with hero amount and field stack.
- `apps/Synnapse-iOS/Features/PositionDetailView.swift` — per-position
  drill-down with market-value hero, signed P/L, and metadata.
- `apps/Synnapse-iOS/Features/Haptics.swift` — UIKit feedback wrapper:
  `tabSwitch`, `refreshComplete`, `drillDown`, `swipeAction`.
- `packages/SynnapseKit/Tests/FeaturesTests/Finance/LedgerStatusScopeTests.swift` —
  6 Swift Testing cases for the new reducers.

### Modified

- `apps/Synnapse-iOS/SynnapseiOSApp.swift` — 4 tabs (Finance / Life /
  Advisors / Settings); selection-binding TabView with `Haptics.tabSwitch`
  on change; new `FinanceTab` rooted at `FinanceHubView`; `LifeTab` is
  full-bleed (`.navigationBarHidden(true)` + `.ignoresSafeArea`);
  Settings is now a tab, not buried under "More".
- `packages/SynnapseKit/Sources/Features/Finance/FinancePersonalView.swift`
  iOS only — large-title nav, accounts rows now drill via
  `NavigationLink(value: account)`, keyboard-dismissing scroll.
- `packages/SynnapseKit/Sources/Features/Finance/FinanceAccountsView.swift`
  iOS only — grouping switched from `AccountKind` to institution (the
  phone mental model); `.swipeActions` for Hide / Sync; large title.
- `packages/SynnapseKit/Sources/Features/Finance/FinanceTransactionsView.swift`
  iOS only — segmented scope picker (All / Pending / Posted), grouped
  by card with collapsible section headers, phone-tuned row (no
  fixed-width column overflow), large title, drill-down to detail.
- `packages/SynnapseKit/Sources/Features/Finance/FinanceInvestmentsView.swift`
  split into `#if os(macOS)` / `#if os(iOS)` branches. iOS gets a
  grouped `List` keyed by `SecurityKind`, drill-down to detail, hero
  row inside the list.
- `packages/SynnapseKit/Sources/Features/Advisors/AdvisorsView.swift`
  iOS only — removed the inner `NavigationStack` (the tab shell owns
  it now); added `.scrollDismissesKeyboard(.interactively)` to the chat
  transcript.

## Boundaries respected

- No macOS-only code touched.
- No `DesignSystem` token overrides — the iOS surfaces inherit Cockpit
  identity via `.identity(.cockpitInstrument)` set at the tab level,
  and Life still carries `.identity(.terminalAmber)`.
- `Package.swift`, `project.yml`, app-shell bootstrap untouched.
- No edits to Life rendering logic (Agent A territory) — only the iOS
  wrapper (`LifeTab`) that hosts it full-bleed.

## Verification

```
swift test --package-path packages/SynnapseKit
# 218 tests in 50 suites pass (was 212; +6 new LedgerStatusScopeTests)

xcodebuild -project Synnapse.xcodeproj -scheme SynnapseiOS \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build
# BUILD SUCCEEDED

xcodebuild -project Synnapse.xcodeproj -scheme SynnapseMac \
  -destination 'generic/platform=macOS' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
# BUILD SUCCEEDED (regression check — macOS shell still compiles)
```

## Departures from the brief

- The brief asks for iOS snapshot coverage of "each major surface in
  light + dark on iPhone 16 Pro and iPad 11" form factors." The existing
  snapshot tests are tuned to iPhone 13 Pro (`as: .image(on: .iPhone13Pro)`)
  and have no iPad variants. I did not introduce new device-family tests
  in this pass because (a) snapshot recording must run on an iOS host
  before any of them would lock, and (b) the iPhone 13 Pro slot is a
  reasonable proxy for iPhone 16 Pro at the layout level — the redesign
  is composition, not pixel-art. iPad variants and the iPhone 16 Pro
  rename can land in a follow-up that runs on an iOS host.
- The brief mentions a per-account "balance history" chart. The
  underlying `FinanceAccount` model carries `balanceCapturedAt` but no
  historical series; I did not invent a stub series. The AccountDetail
  screen shows the recent transactions list as the only visualization
  for now.
- Per-position price history likewise omitted — `InvestmentPosition`
  has no history field.
- The "iMessage-style bubbles" already existed in `MessageBubble`. The
  only iOS-specific addition is `.scrollDismissesKeyboard(.interactively)`
  on the transcript.
