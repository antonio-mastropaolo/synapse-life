# M8 Integration Manifest — Advisors + Octagon + Trading Desk

Scope of this worktree: three new surfaces. All files are additive — no
existing M1–M6 file was modified. The integrator can pick this commit up
without resolving conflicts against the M7 sibling.

Branch: `worktree-m8-advisors-octagon-trading`
Commit: `feat(advisors+octagon+trading-desk): three new surfaces — M8 (test-first)`

## Test counts

| State | Tests | Suites |
| ---: | ---: | ---: |
| Entering main | 194 | 41 |
| Exiting M8 (macOS / SPM) | **253** | **55** |
| Added by M8 | **59** | **14** |
| Snapshot PNG refs added | **24** | — |

## Files created

### Models (new types only)

- `packages/SynapseLifeKit/Sources/Models/Advisor.swift` — `Advisor`,
  `AdvisorsResponse`, `ChatMessage`, `MessageRole`
- `packages/SynapseLifeKit/Sources/Models/OctagonVendor.swift` —
  `OctagonVendor` (with nested `HQ`, `Financing`, `CEO`),
  `OctagonBriefEnvelope`, `MembershipCard` (with `Cadence`, `Status`),
  `MembershipsResponse`

### Networking

- `packages/SynapseLifeKit/Sources/Networking/AdvisorsAPI.swift` — protocol
  + `LiveAdvisorsAPI` + `MockAdvisorsAPI` + `SSEParser` + `ChatDelta`
- `packages/SynapseLifeKit/Sources/Networking/OctagonAPI.swift` — protocol
  + `LiveOctagonAPI` + `MockOctagonAPI`

### Features

- `packages/SynapseLifeKit/Sources/Features/Advisors/AdvisorsListViewModel.swift`
- `packages/SynapseLifeKit/Sources/Features/Advisors/StreamingChatViewModel.swift`
- `packages/SynapseLifeKit/Sources/Features/Advisors/AdvisorsView.swift`
- `packages/SynapseLifeKit/Sources/Features/Octagon/OctagonViewModel.swift`
- `packages/SynapseLifeKit/Sources/Features/Octagon/OctagonView.swift`
- `packages/SynapseLifeKit/Sources/Features/Finance/TradingDeskViewModel.swift`
  (NEW file — does NOT touch any existing M5 Finance files)
- `packages/SynapseLifeKit/Sources/Features/Finance/TradingDeskView.swift`

### Tests

- `packages/SynapseLifeKit/Tests/ModelsTests/AdvisorTests.swift`
- `packages/SynapseLifeKit/Tests/ModelsTests/OctagonVendorTests.swift`
- `packages/SynapseLifeKit/Tests/NetworkingTests/AdvisorsRepositoryTests.swift`
- `packages/SynapseLifeKit/Tests/NetworkingTests/OctagonRepositoryTests.swift`
- `packages/SynapseLifeKit/Tests/FeaturesTests/Advisors/StreamingChatViewModelTests.swift`
- `packages/SynapseLifeKit/Tests/FeaturesTests/Octagon/OctagonViewModelTests.swift`
- `packages/SynapseLifeKit/Tests/FeaturesTests/Finance/TradingDeskViewModelTests.swift`
- `packages/SynapseLifeKit/Tests/SnapshotTests/AdvisorsScreenSnapshotTests.swift`
- `packages/SynapseLifeKit/Tests/SnapshotTests/OctagonScreenSnapshotTests.swift`
- `packages/SynapseLifeKit/Tests/SnapshotTests/TradingDeskScreenSnapshotTests.swift`

### Snapshot reference PNGs (24 total)

- `AdvisorsScreenSnapshotTests/` — 12 PNGs (mac+iOS × light+dark × idle/ready/streaming)
- `OctagonScreenSnapshotTests/` — 8 PNGs (mac+iOS × light+dark × list/inspector)
- `TradingDeskScreenSnapshotTests/` — 4 PNGs (mac × light+dark + iOS placeholder × light+dark)

## What the integrator must do

### Package wiring

**Nothing.** No new targets, no new products. All source lives under the
existing `Models`, `Networking`, and `Features` target paths and is picked
up by SwiftPM's directory-based target discovery. `Package.swift` is
unchanged.

### App wiring

The new surfaces are not yet attached to the app shells. Per the M8
brief, the integrator should:

#### iOS (`apps/Synapse-iOS/SynapseiOSApp.swift`)

- Replace the "Advisors" placeholder tab (if present from M1) with:
  ```swift
  AdvisorsView(viewModel: AdvisorsListViewModel(api: liveAdvisorsAPI))
  ```
- Add an "Octagon" tab:
  ```swift
  OctagonView(viewModel: OctagonViewModel(api: liveOctagonAPI))
  ```
- For the "Trading Desk" entry on iOS, present the placeholder:
  ```swift
  TradingDeskPlaceholderView()
  ```

#### macOS (`apps/Synapse-macOS/SynapseMacApp.swift`)

Three new `WindowGroup`s with keyboard shortcuts:

```swift
WindowGroup("Advisors", id: "advisors") {
    AdvisorsView(viewModel: AdvisorsListViewModel(api: liveAdvisorsAPI))
}
.keyboardShortcut("7", modifiers: .command)

WindowGroup("Octagon", id: "octagon") {
    OctagonView(viewModel: OctagonViewModel(api: liveOctagonAPI))
}
.keyboardShortcut("8", modifiers: .command)

WindowGroup("Trading Desk", id: "trading-desk") {
    TradingDeskView(viewModel: TradingDeskViewModel(api: liveFinanceAPI))
}
.keyboardShortcut("9", modifiers: .command)
```

The `liveAdvisorsAPI` and `liveOctagonAPI` should be constructed against
the same shared `APIClient` actor that backs Spotlight/Finance:

```swift
let liveAdvisorsAPI = LiveAdvisorsAPI(client: apiClient)
let liveOctagonAPI  = LiveOctagonAPI(client: apiClient, membershipsContractLive: false)
```

`membershipsContractLive: false` is correct as of M8 — the synapse-v2
server has not landed `/api/finance/memberships` yet. The Octagon UI
will render its empty state until that route ships; flipping the flag
will make it live without any other code change.

## Server contracts

| Route | State | Notes |
| --- | --- | --- |
| `GET /api/ai-advisors` | **Live** in synapse-v2 (`app/api/ai-advisors/route.ts`). | Native decoder is forward-compat for `lastActiveAt` (ms / seconds / ISO). |
| `POST /api/ai-advisors/[id]/chat` | **Live** in synapse-v2. SSE shape `data: {"text":"..."}` and `data: {"done":true,"threadId":"..."}`. | Native parser is forward-compat — handles `{"error":...}` events and trailing fragments without a final `done`. |
| `GET /api/finance/octagon/[vendor]` | **Live** in synapse-v2 (`app/api/finance/octagon/[vendor]/route.ts`). | Vendor name is URL-encoded; 24h server cache. |
| `GET /api/finance/memberships` | **Forward-compat (404-tolerant).** | Web app derives memberships client-side from transactions today; native client returns `[]` until the contract lands. Toggle `LiveOctagonAPI(membershipsContractLive:)` to opt in. |
| Quote history (Trading Desk chart) | **Synthetic deterministic walk.** | `TradingDeskViewModel.intradayPoints(for:)` paints a per-ticker walk anchored at the position's last price. Swap for `/api/finance/quote-history` when ready. |

## Departures from the brief

None of substance. Two implementation notes worth surfacing:

1. **macOS Advisors split view** — the brief asked for a sidebar list +
   chat pane. macOS `NavigationSplitView` doesn't snapshot cleanly as a
   single screen (the AppKit detail-column host is opaque to
   `NSHostingView` at capture time). The `advisors.streaming.{light,dark}.mac.png`
   references therefore lock the **chat pane in isolation**; the
   full-screen wiring stays in `AdvisorsView.macLayout` and is exercised
   by the iOS NavigationStack snapshot.

2. **iOS Octagon inspector** — opens as a `.sheet(detents: [.medium, .large])`.
   The snapshot suite captures the `OctagonInspector` view directly so
   the layout is locked even when sheet presentation isn't part of the
   render tree; the sheet wrapper is still wired in `OctagonView.iosLayout`.

## Test commands

```bash
# Full macOS suite via SPM:
swift test --package-path packages/SynapseLifeKit

# iOS snapshot suite (against an iPhone-class sim — viewport is locked
# by snapshot config to 1170×2532 regardless of the actual simulator):
xcodebuild test \
  -workspace SynapseLife.xcworkspace \
  -scheme SnapshotTests \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro"
```
