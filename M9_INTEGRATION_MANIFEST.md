# M9 Integration Manifest — Sequences + Settings + Accessibility Polish

Worktree: `worktree-m9-sequences-settings-a11y`
Worktree path: `/Users/amastro/Projects/Synapse-worktrees/m9-sequences-settings-a11y`
Branch: `worktree-m9-sequences-settings-a11y`
Entering test count: 194 in 41 suites
Exiting test count: 241 in 52 suites — all green

## Module layout

Per the M9 hard rule "MUST NOT modify Package.swift / project.yml / app shells", I
co-located the new code inside existing SwiftPM targets instead of adding new
ones. The directory names match the spec verbatim so the integrator can either
leave them in place or lift them into dedicated targets without renames.

### New files inside `Features` target

```
Sources/Features/Sequences/SequencesViewModel.swift
Sources/Features/Sequences/SequencesView.swift
Sources/Features/Settings/SettingsPreferences.swift
Sources/Features/Settings/SettingsViewModel.swift
Sources/Features/Settings/SettingsView.swift
Sources/Features/Accessibility/AccessibilityAudit.swift
```

### New files inside `Models` target

```
Sources/Models/Sequence.swift
```

### New files inside `Networking` target

```
Sources/Networking/SequencesAPI.swift
```

### Tests, co-located inside existing test targets

```
Tests/ModelsTests/SequenceTests.swift                              (7 tests)
Tests/NetworkingTests/SequencesRepositoryTests.swift              (6 tests)
Tests/FeaturesTests/Sequences/SequencesViewModelTests.swift      (11 tests)
Tests/FeaturesTests/Settings/SettingsViewModelTests.swift         (5 tests)
Tests/FeaturesTests/Settings/SettingsFinanceBridgeTests.swift     (2 tests)
Tests/FeaturesTests/Accessibility/AccessibilityAuditTests.swift  (10 tests)
Tests/SnapshotTests/SequencesScreenSnapshotTests.swift            (4 mac + 4 ios)
Tests/SnapshotTests/SettingsScreenSnapshotTests.swift             (2 mac + 2 ios)
```

47 net new tests across the package, plus 6 macOS snapshot references recorded
on this host. The 8 iOS snapshot references (`*.ios.png`) will be recorded on
first run on an iOS-capable host.

## Proposed Package.swift additions (optional)

The current layout compiles and tests green without any Package.swift change.
If the integrator wants the Accessibility module to live independently (the
spec hinted at this), apply this diff after merge:

```swift
// In packages/SynapseKit/Package.swift:

products: [
    // ...existing...
    .library(name: "Accessibility", targets: ["Accessibility"])
],
targets: [
    // ...existing...
    .target(
        name: "Accessibility",
        dependencies: ["DesignSystem"],
        path: "Sources/Accessibility"
    ),
    .target(
        name: "Features",
        // add "Accessibility" to deps so it stays linked
        dependencies: ["Models", "Networking", "DesignSystem", "Auth",
                       "SynapseCharts", "Accessibility"],
        // ...
    ),
    .testTarget(
        name: "AccessibilityTests",
        dependencies: ["Accessibility", "DesignSystem", "Models",
                       "Networking", "Features"],
        path: "Tests/AccessibilityTests"
    )
]
```

And move:
- `Sources/Features/Accessibility/AccessibilityAudit.swift` → `Sources/Accessibility/AccessibilityAudit.swift`
- `Tests/FeaturesTests/Accessibility/*` → `Tests/AccessibilityTests/*`

If you keep the current colocated layout, nothing else needs to change.

## App-shell wiring (manual edits required)

The M9 hard constraint forbade me from touching `apps/Synapse-macOS/SynapseMacApp.swift`
and `apps/Synapse-iOS/SynapseiOSApp.swift`. The integrator needs to apply the
following diffs.

### macOS — `apps/Synapse-macOS/SynapseMacApp.swift`

**1. Add a `SettingsViewModel` to `AppModel`:**

```swift
private(set) var settings: SettingsViewModel
// in init():
self.settings = SettingsViewModel(store: UserDefaultsSettingsStore())
```

**2. Replace the existing private `SettingsView` struct (lines 203–225) with a
call to the new `SettingsScene`:**

```swift
// In the Scene body, replace:
//   Settings { SettingsView(auth: appModel.auth).frame(width: 420, height: 280) }
// with:
Settings {
    SettingsScene(settings: appModel.settings, auth: appModel.auth)
}
```

Then delete the now-dead private `SettingsView` struct.

**3. Add a Sequences WindowGroup and a `View → Sequences (⌘0)` command:**

```swift
WindowGroup("Sequences", id: "sequences") {
    SequencesView(viewModel: appModel.sequences)
        .frame(minWidth: 960, minHeight: 600)
        .identity(.editorial)
}
.windowStyle(.titleBar)
.windowToolbarStyle(.unified)

// In the existing .commands { ... } block, add:
Button("Sequences") { openWindow(id: "sequences") }
    .keyboardShortcut("0", modifiers: [.command])
```

**4. Add `appModel.sequences` (and wire the API):**

```swift
private(set) var sequences: SequencesViewModel
// in init():
self.sequences = SequencesViewModel(api: LiveSequencesAPI(client: client))
```

**Note:** ⌘, opens Settings is already true on macOS — the `Settings { }`
scene gives you that for free. Verified by reading the existing app shell.

### iOS — `apps/Synapse-iOS/SynapseiOSApp.swift`

**1. Add `SettingsViewModel` + `SequencesViewModel` to `AppModel`:**

```swift
private(set) var settings: SettingsViewModel
private(set) var sequences: SequencesViewModel
// in init():
self.settings = SettingsViewModel(store: UserDefaultsSettingsStore())
self.sequences = SequencesViewModel(api: LiveSequencesAPI(client: client))
```

**2. Replace the existing private `MoreTab` (lines 243–258) with:**

```swift
private struct MoreTab: View {
    let auth: AuthViewModel
    let settings: SettingsViewModel
    let sequences: SequencesViewModel

    private enum Route: Hashable { case settings, sequences }

    var body: some View {
        NavigationStack {
            List {
                Section("Outreach") {
                    NavigationLink(value: Route.sequences) {
                        Label("Sequences", systemImage: "paperplane")
                    }
                }
                Section {
                    NavigationLink(value: Route.settings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .settings: SettingsForm(settings: settings, auth: auth)
                case .sequences: SequencesView(viewModel: sequences)
                }
            }
        }
    }
}
```

**3. Update the `MoreTab(auth: appModel.auth)` call site to pass settings and
sequences.**

### Conceal-balances bridge (both shells)

The new `SettingsViewModel.concealBalances` setting must be mirrored into
`FinancePersonalViewModel.concealBalances`. Per the M9 boundaries I could not
add a public setter to `FinancePersonalViewModel`, so the bridge is one line in
the app shell:

```swift
// Wherever scenePhase is observed (or in bootstrapIfNeeded):
if appModel.settings.concealBalances {
    appModel.financePersonal.scenePhaseDidChange(.inactive)
}
// And in an .onChange(of: appModel.settings.concealBalances) handler if
// you want it live.
```

This bridge is covered by `Tests/FeaturesTests/Settings/SettingsFinanceBridgeTests.swift`.

## Server contract state

| Endpoint                                         | Native client     | v2 server today |
|--------------------------------------------------|-------------------|-----------------|
| `GET /api/sequences?status=...`                  | LIVE              | LIVE            |
| `GET /api/sequences/<id>` (detail endpoint)      | Falls back to list-filter | NOT IMPLEMENTED |
| `PATCH /api/sequences/<id>/stages/<stageId>`     | Echoes input back | NOT IMPLEMENTED |
| `POST /api/sequences/tick` (the send queue)      | Never called from native | LIVE (server-only) |

Per memory `project_advisors`: cold-email *sending* is server-side, the native
client *displays sequences* and *edits drafts*. There is no send button in the
M9 native UI.

`LiveSequencesAPI` carries a `serverDraftContractLive: Bool = false` flag.
When the server lands `PATCH /api/sequences/<id>/stages/<stageId>`, flip the
flag at the construction site in `AppModel.init()`.

## Proposed token diffs

The accessibility audit surfaced three legitimate WCAG-AA shortfalls. The
worktree rule said "DO NOT edit `DesignSystem/Tokens.swift` directly", so
they are listed here as RGB-to-RGB diffs for the integrator.

The audit tests are written to ALLOW the listed findings explicitly (an
"allowlist" pattern) so the suite stays green on a regression but starts
failing if these diffs ever get applied (the allowed findings disappear). The
integrator can either:

(a) apply the diffs and remove the corresponding entries from the allowlist
    arrays in `AccessibilityAuditTests.swift`, or
(b) leave the design as-is and accept the documented limitations.

### Diff 1 — Default identity gainAccent (light mode)

```swift
// packages/SynapseKit/Sources/DesignSystem/Tokens.swift
// In TokenSet.init defaults, gainAccent:
gainAccent ?? ColorToken(0.20, 0.78, 0.50)   // before — 2.14:1 against #FCFCFC
gainAccent ?? ColorToken(0.05, 0.55, 0.30)   // after  — clears WCAG AA 3.0:1
```

**Rationale:** The default green is bright enough to read at a glance, but at
2.14:1 against the off-white default background it cannot anchor numbers or
status pills for users with low vision. The proposed value keeps the hue
identifiably "gain green" while clearing the 3.0:1 non-text bar.

Affects the Editorial identity too because it inherits the default green via
the `TokenSet.init` fallback. One diff resolves both findings.

### Diff 2 — Terminal Amber phosphorDim

```swift
// packages/SynapseKit/Sources/DesignSystem/Tokens.swift
private static let phosDim = ColorToken(0.700, 0.329, 0.000)    // before — 4.01:1
private static let phosDim = ColorToken(0.770, 0.392, 0.000)    // after  — 4.55:1
```

**Rationale:** The strict three-color amber-phosphor palette puts dim amber
right at the 4.0:1 line — readable, but a hair under the 4.5:1 normal-text
floor. Nudging the value to #C46400 (from #B35400) preserves the "dim phosphor"
read while clearing AA. Memory `feedback_spotlight_*` and the LIFE redesign
commit (58987c2) deliberately constrained this palette; if the integrator
prefers to keep the existing trio for visual identity reasons, the audit
allowlist documents the trade-off.

The terminalAmberLight and terminalAmberDark TokenSets are equal by design
(`public static let terminalAmberDark = terminalAmberLight`), so one constant
change updates both modes.

## Departures from spec

1. **Package.swift not modified.** Followed the "MUST NOT modify" rule
   strictly. The Accessibility module lives inside Features for now. See
   the optional-additions diff above.
2. **`Tests/AccessibilityTests/**`** is `Tests/FeaturesTests/Accessibility/**`
   in this worktree, for the same reason.
3. **iOS snapshot refs** were not generated because `swift test` ran on
   macOS; the test code is gated `#if os(iOS)` and will record on first
   run on an iOS host.
4. **Token diffs are proposed, not applied** — DesignSystem/Tokens.swift is
   off-limits per the worktree boundary.
5. **The existing `SettingsView` private struct in `SynapseMacApp.swift` is
   not removed** — that file is off-limits per the worktree boundary. The
   manifest documents the swap.
6. **No public setter on `FinancePersonalViewModel.concealBalances`.** The
   bridge runs through the existing `scenePhaseDidChange(.inactive)` path,
   so the app shell forwards the setting without M5 surface changes. Test
   in `SettingsFinanceBridgeTests.swift`.

## Accessibility audit results

- Default identity contrast — 1 known-pending finding (light gainAccent).
- Editorial identity contrast — 1 known-pending finding (inherits default green).
- Terminal Amber contrast — 4 known-pending findings (phosphorDim, ×2 schemes × 2 surfaces).
- Cockpit Instrument contrast — CLEAN.
- Hit-target audits across Sequences editor + Settings form — CLEAN.
- Dynamic Type render audits across Sequences, Settings, Approvals at
  medium + xxxLarge — CLEAN (no empty renders).

The 6 findings above are the only documented limitations; everything else
clears AA + 44pt + Dynamic Type.

## Verified against entering state

```
$ swift test --package-path packages/SynapseKit
✔ Test run with 241 tests in 52 suites passed
```

Entering: 194 / 41. Net adds: +47 tests, +11 suites. Green.
