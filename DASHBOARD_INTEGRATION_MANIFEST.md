# Dashboard Integration Manifest

Owner: agent 2 of 5 (Copilot redesign — Dashboard inbox + iOS 5-tab shell).

Branch: `worktree-copilot-dashboard`.

## What this worktree ships

A new `Features/Dashboard` module that renders the Copilot-style inbox
of un-reviewed transactions, plus a reshape of the iOS app to a
5-tab bottom rail.

### Module map

```
packages/SynnapseKit/Sources/Features/Dashboard/
├── DashboardEntry.swift              value type wrapping Transaction + reviewed flag
├── DashboardSection.swift            one date bucket
├── DashboardViewModel.swift          @Observable; selection + projection + mark-reviewed
├── DashboardDemoData.swift           30+ unreviewed rows across 7 days, 4 accounts
├── DashboardCategoryPalette.swift    category → pill colour (local fallback)
├── DashboardCategoryPill.swift       one colored capsule
├── DashboardRowView.swift            inbox row (checkbox + merchant + pill + amount)
├── DashboardInspectorView.swift      right column (Goals + Net this month)
└── DashboardView.swift               public top-level surface (macOS + iOS branches)
```

```
apps/Synnapse-iOS/
├── SynnapseiOSApp.swift              5-tab RootTabView + DashboardViewModel in AppModel
└── Features/
    ├── ComingSoonView.swift          honest placeholder for unowned surfaces
    └── MoreTab.swift                 More-tab drill-down list
```

## How the macOS integrator wires this in

Two pieces of glue are expected from agent 1 (DesignSystem +
RootShellViewModel):

1. **`RootDestination.dashboard` case** in `RootShellViewModel`.
   When the user taps the new "Dashboard" sidebar row, route to
   the case below.

2. **macOS shell detail-pane switch** — render `DashboardView`
   when the selection is `.dashboard`. Adapter pattern:

   ```swift
   case .dashboard:
       DashboardView(viewModel: appModel.dashboard) {
           appModel.shell.select(.goals)   // when agent 4 lands Goals
       }
   ```

3. **Sidebar item** with an unreviewed-count badge. The view model
   exposes `selectionCount` (selected) and the count of unreviewed
   entries is derivable from `entries.filter { !$0.reviewed }.count`
   — a new `unreviewedCount` accessor is on the roadmap for the
   integrator.

## What I did NOT depend on

- I did NOT touch `DesignSystem` (per the parallel-agent contract).
- I did NOT touch `Features/Categories`, `Features/Subscriptions`,
  `Features/Recurrings`, `Features/Goals`, `Features/CashFlow`,
  `Features/AI`, `Features/Digest`, `Features/Forecast` (other
  agents own these).
- I did NOT touch `apps/Synnapse-macOS/**`.
- I did NOT edit `Features/Finance/Transactions*` files. The
  Dashboard reads `Transaction` and `TransactionCategory` from
  `Models` only.

## Category-colour palette

`DashboardCategoryPalette.fill(for:tokens:)` ships with a
self-contained palette (RESTAURANTS / SUBSCRIPTIONS / GROCERIES /
LOANS / CLOTHING / INCOME / SHOPPING / TRANSPORT / ENTERTAINMENT /
TRANSFER / PERSONAL CARE / FEES). When agent 1 adds
`tokens.category(_:)` on `TokenSet`, the swap is one line inside
`DashboardCategoryPalette.fill`.

## iOS 5-tab shape

| # | Tab           | SF Symbol                          | Backing view                                |
|---|---------------|------------------------------------|---------------------------------------------|
| 1 | Dashboard     | `square.grid.2x2`                  | `DashboardView(viewModel: appModel.dashboard)` |
| 2 | Transactions  | `list.bullet.indent`               | `FinanceTransactionsView`                   |
| 3 | Cash flow     | `chart.line.uptrend.xyaxis`        | `ComingSoonView` (agent 4 lands real surface) |
| 4 | Investments   | `briefcase`                        | `FinanceInvestmentsView`                    |
| 5 | More          | `ellipsis.circle`                  | `MoreTab` (drills into all other surfaces)  |

More-tab contents (drill-down list, in display order):
- Money: Personal, Accounts, Goals (coming soon), Subscriptions
  (coming soon), Recurrings (coming soon), Categories (coming soon)
- Life: Life terminal, Advisors
- System: Settings

Selection haptic fires on tab change
(`UISelectionFeedbackGenerator().selectionChanged()` via
`Haptics.tabSwitch()`).

## Test surface

| Suite                       | Tests | Where                                                      |
|-----------------------------|-------|------------------------------------------------------------|
| `DashboardViewModel`        | 10    | `Tests/FeaturesTests/Dashboard/DashboardViewModelTests.swift` |
| `DashboardDemoData`         | 8     | `Tests/FeaturesTests/Dashboard/DashboardDemoDataTests.swift` |
| `DashboardScreenSnapshot`   | 3 mac + 2 iOS | `Tests/SnapshotTests/DashboardScreenSnapshotTests.swift` |

23 net-new tests. Full SwiftPM test run on macOS host: 301 / 301
green (60 suites).

## Notable departures from the brief

1. **Server contract not stubbed**: the brief implies a server
   path for the dashboard inbox. None exists today on synapse-v2.
   The view model exposes a `load(_:)` entry point that takes the
   shape a future repository will produce; the demo data path is
   the only seed today. Document `reference_dashboard_api.md` in
   memory once the route lands.

2. **Per-row navigation**: Copilot's row taps select; they don't
   push a detail view. I matched that. If product wants a row tap
   to push `TransactionDetailView` AND a checkbox tap to select,
   the row's `.onTapGesture` becomes a `Button` and the checkbox
   becomes an independent `Toggle` inside it — a 4-line change.

3. **Category palette is local**, not in `DesignSystem`. See the
   "Category-colour palette" note above for the swap path.

4. **Net this month** in the inspector uses the view model's own
   ledger (the seeded demo data). Once the dashboard reads from
   the live ledger, agent 1's `FinancePersonalViewModel.netThisMonth`
   should become the source of truth and the inspector should
   adopt a `cashFlowProvider: () -> Decimal` adapter closure.
