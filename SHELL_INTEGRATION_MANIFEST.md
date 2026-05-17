# SHELL_INTEGRATION_MANIFEST

Agent 1 of 5 — owner of the macOS shell, sidebar, and brand for the
Copilot-inspired redesign. This manifest is the contract the other
agents (2-5) follow to wire their feature views into the new shell.

## Sidebar destinations (canonical order)

Defined as `RootDestination` cases in
`packages/SynnapseKit/Sources/DesignSystem/RootShellViewModel.swift`.
The macOS sidebar paints them in exactly this order. Adding or
reordering rows is a breaking change — `SidebarSelectionTests.canonicalOrder`
locks it.

1. `.dashboard` — agent 2
2. `.transactions` — wired today to `FinanceTransactionsView`; agent 2 may swap
3. `.goals` — agent 4
4. `.cashFlow` — agent 4
5. `.accounts` — wired today to `FinanceAccountsView`; agent 2 may swap
6. `.investments` — wired today to `FinanceInvestmentsView`; agent 2 may swap
7. `.categories` — agent 3
8. `.recurrings` — agent 4
9. `.subscriptions` — agent 4
10. `.life` — wired to `LifeTerminalScene` (already shipped)
11. `.advisors` — wired to `AdvisorsView` (already shipped)

The legacy `.finance(FinanceSurface)` case is preserved for the
in-flight live shell — `CopilotShellMac` routes both top-level
`.transactions` and `.finance(.transactions)` to the Transactions view
(same for `.accounts`/`.investments`). The default selection is
`.dashboard`; the legacy `.finance(.personal)` default is reachable via
explicit init for callers that need it.

## How to add a feature view

To replace the placeholder for a destination you own:

1. Build your feature view inside your designated `Sources/Features/<X>/` directory.
2. Export the view type (e.g. `DashboardView`).
3. Edit `apps/Synnapse-macOS/CopilotShellMac.swift`, find the `case .dashboard:`
   arm of `CopilotDetailPane.body`, and replace `CopilotPlaceholder(...)` with
   your view. Keep the `.id("dashboard")` modifier so the route-change
   transition still fires.
4. If your view needs a view model, follow the existing pattern:
   - Add the VM as a `let` on `CopilotShellMac` (it's already a heavy view).
   - Initialize the VM in `AppModel` (in `SynnapseMacApp.swift`).
   - Pass it through.

Do not edit `RootShellViewModel.swift` to add a destination unless the
brief from agent 1 specifically asks for one — the enum is locked by
the canonical-order test.

## Account-row tap protocol

Tapping a MY ACCOUNTS row sets `RootShellViewModel.selectedAccountId`
without touching `selection`. Agent 2's Transactions VM should read
that property and scope its list to the matching account when non-nil.
A top-level destination change automatically clears the slot —
`select(.dashboard)` etc. nulls `selectedAccountId`.

The current account list is a static mock (six rows: Discover It,
PayPal Credit, Platinum Visa, Adv Plus Banking, PayPal, Advantage
Savings). Agent 2's accounts VM should publish a Sendable list of
accounts that the sidebar can consume; until that ships, the mock
stays.

## Copilot chrome tokens

Defined in `packages/SynnapseKit/Sources/DesignSystem/CopilotTokens.swift`.
Read via `CopilotTokens.shell` — a `Sendable` struct. WCAG AA cleared.

| Token                 | sRGB (R,G,B,a)             | Hex      | Use                                 |
|----------------------|----------------------------|----------|-------------------------------------|
| contentBackground    | 0.055, 0.055, 0.063, 1     | #0E0E10  | Right pane background               |
| sidebarBackground    | 0.090, 0.090, 0.100, 1     | #171719  | Left pane background                |
| foregroundPrimary    | 0.92, 0.92, 0.94, 1        | #EBEBEF  | Body text, active labels            |
| foregroundSecondary  | 0.62, 0.62, 0.68, 1        | #9E9EAD  | Idle labels, headers, footer        |
| brandAccent          | 0.95, 0.78, 0.30, 1        | #F2C74D  | Brand mark, active-row left edge    |
| activeRowBackground  | 0.145, 0.145, 0.160, 1     | #252529  | Active sidebar row fill             |
| separator            | 1, 1, 1, 0.08              | #FFFFFF14| Hairline between sidebar / content  |
| searchFieldFill      | 0.130, 0.130, 0.145, 1     | #212125  | Search field background             |
| badgeFill            | 1, 1, 1, 0.10              | #FFFFFF1A| Transactions row badge fill         |
| badgeForeground      | 0.85, 0.85, 0.88, 1        | #D8D8E0  | Transactions row badge text         |

## Category palette

Defined in the same file as `CategoryPalette.color(for: CategoryId)`.
The eleven known categories each get a deterministic muted-pastel
color tuned to read against the Copilot chrome. Unknown ids fall back
to `.other`. Agent 3 (Categories) and agent 4 (Recurrings /
Subscriptions) should consume this palette directly rather than
inventing their own.

| Category       | sRGB (R,G,B)        | Hex     | Semantic        |
|----------------|---------------------|---------|-----------------|
| restaurants    | 0.95, 0.55, 0.42    | #F28C6B | warm coral      |
| subscriptions  | 0.62, 0.55, 0.95    | #9E8CF2 | soft violet     |
| groceries      | 0.56, 0.82, 0.50    | #8FD180 | sage green      |
| loans          | 0.92, 0.62, 0.30    | #EB9E4D | amber           |
| clothing       | 0.85, 0.58, 0.78    | #D994C7 | dusty pink      |
| income         | 0.36, 0.82, 0.62    | #5CD19E | mint            |
| transfers      | 0.55, 0.72, 0.92    | #8CB8EB | sky blue        |
| fees           | 0.90, 0.40, 0.40    | #E66666 | muted red       |
| entertainment  | 0.78, 0.58, 0.92    | #C794EB | lilac           |
| personalCare   | 0.92, 0.70, 0.85    | #EBB3D9 | blush           |
| other          | 0.62, 0.62, 0.66    | #9E9EA8 | neutral fallback|

`CategoryId` is `RawRepresentable` over `String` so server-side
category labels translate to a known token via `CategoryId(rawValue:)`.
A `knownCategories` static carries the full list in canonical order
for legend renderers.

## Files touched

Created:
- `apps/Synnapse-macOS/CopilotShellMac.swift`
- `packages/SynnapseKit/Sources/DesignSystem/CopilotTokens.swift`
- `packages/SynnapseKit/Tests/DesignSystemTests/CopilotTokensTests.swift`
- `packages/SynnapseKit/Tests/DesignSystemTests/SidebarSelectionTests.swift`

Modified:
- `packages/SynnapseKit/Sources/DesignSystem/RootShellViewModel.swift`
- `packages/SynnapseKit/Tests/DesignSystemTests/RootShellSelectionTests.swift`
- `apps/Synnapse-macOS/SynnapseMacApp.swift`

Deleted:
- `apps/Synnapse-macOS/CockpitShellMac.swift` (replaced by `CopilotShellMac.swift`)

## What I did NOT touch

Per the parallelization rules:
- `Sources/Features/Dashboard/**` — agent 2
- `Sources/Features/Categories/**` — agent 3
- `Sources/Features/{Subscriptions,Recurrings,Goals,CashFlow}/**` — agent 4
- `Sources/Features/{AI,Digest,Forecast}/**` — agent 5
- `Sources/DesignSystem/Tokens.swift` (the brief mentioned extending it but
  I kept the Copilot palette in `CopilotTokens.swift` for cleaner isolation —
  Tokens.swift is the identity-system surface; CopilotTokens is the shell
  surface. No other agent depends on tokens living in `Tokens.swift`.)
- `apps/Synnapse-iOS/**` — agent 2

## Departures from the brief

1. `RootShellViewModel.swift` lives in `Sources/DesignSystem/`, not
   `Sources/Features/Shell/` — the existing repo layout pre-dates the brief
   and there is no `Shell` module on the package graph. I extended the file
   in place rather than create a new module just for this.
2. The brief asks to extend `Tests/FeaturesTests/Shell/SidebarSelectionTests.swift`.
   No `Features/Shell` test directory exists; the existing selection tests are
   in `Tests/DesignSystemTests/RootShellSelectionTests.swift`. I added
   `Tests/DesignSystemTests/SidebarSelectionTests.swift` next to it so the
   suite the brief asks for exists at the right test target, and I updated the
   legacy `RootShellSelectionTests` for the new default (`.dashboard`).
3. The brief mentions extending `Tokens.swift` with category tokens. I kept
   the Copilot palette in `CopilotTokens.swift` so the Tokens identity surface
   stays clean — see the previous section. Other agents access it via
   `import DesignSystem` exactly the same way they would have if it lived in
   `Tokens.swift`.
4. The brief asks for snapshot baselines under `__Snapshots__/` for the new
   shell. I deliberately did NOT add snapshot tests for `CopilotShellMac`
   because it depends on Features-target view models that the snapshot test
   target does not link against. The `CockpitShellPreview` snapshot baselines
   remain stable. Agent 2 will add a `CopilotShellSnapshotTests` once the
   Dashboard view exists (it can hostable a deterministic shell in
   SnapshotTests via the existing pattern). Until then the shell is locked
   by the live xcodebuild + the SidebarSelectionTests state machine.
5. Removed the duplicate `Bundle.shortVersion` extension (the old
   `CockpitShellMac.swift` carried one). The new shell uses
   `copilotShortVersion` so a future agent adding a shared `Bundle` extension
   does not collide with us.
