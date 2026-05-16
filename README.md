# Synnapse

Native Apple-platform reframe of [synapse-v2](https://github.com/antonio-mastropaolo/synapse-v2).
iOS and macOS today; iPadOS, visionOS, and watchOS deferred to later
milestones. The client talks to a synapse-v2 server over HTTP; the
Cockpit Dense identity (deep black + amber-phosphor cues) is the
default visual language. Sign in with Apple is the only supported
auth path.

## Layout

- `packages/SynnapseKit/` — shared Swift package. Modules:
  - `Models` — Sendable domain types and money primitives.
  - `Networking` — `APIClient`, `Endpoint`, typed live API clients.
  - `Auth` — `KeychainStore`, `SessionStore`, Sign in with Apple bridge.
  - `Persistence` — local stores.
  - `DesignSystem` — `Theme`, `Identity`, `Tokens`, `contrastRatio`.
  - `SynnapseCharts` — chart primitives for the Finance and Octagon surfaces.
  - `Features` — every view model + view (Spotlight, Approvals, Finance, Life, People, Inbox, Advisors, Octagon, Sequences, Settings).
  - `AppLifecycle` — `AppCore` (cross-platform construction seam), `DeepLink`, `RestorationPayload`, `AppLifecycleService`.
  - `Tools` — `IconRenderer` for the placeholder app icon (macOS-only target).
- `apps/Synnapse-macOS/` — macOS app shell. Multi-window via SwiftUI `WindowGroup` + global `⌘⇧Space` Spotlight hotkey.
- `apps/Synnapse-iOS/` — iOS app shell. Five-tab `TabView` with a `More` tab for surfaces that didn't earn a top-level slot.
- `apps/Shared/` — code shared between the two app targets.
- `project.yml` — xcodegen spec. Regenerate the Xcode project with `xcodegen generate`.
- `scripts/` — `make-icons.swift`, `release-macos.sh`, `release-ios.sh`. See `scripts/README.md`.

## Build

```
brew install xcodegen
xcodegen generate
open Synnapse.xcworkspace
```

Pick the `SynnapseMac` or `SynnapseiOS` scheme. The default base URL
is `http://localhost:3000/`; override with the `SYNNAPSE_API_BASE`
environment variable on the scheme.

## Test

```
swift test --package-path packages/SynnapseKit
```

Snapshot references live under `packages/SynnapseKit/Tests/SnapshotTests/__Snapshots__/`.
Per-surface snapshots are split into mac and iOS variants; the test
runner records new references when missing rather than failing, so
the first run on a new platform produces baseline images.

## Release

The signing infrastructure is wired up; actual archival is left to
the user because it requires Apple Developer credentials.

- `./scripts/release-macos.sh` — archives, exports, notarises, and
  staples the macOS app for Developer ID distribution.
- `./scripts/release-ios.sh` — archives, exports, and uploads the iOS
  app to TestFlight via `xcrun altool`.
- `./scripts/make-icons.swift` — re-renders the Cockpit-amber app
  icon set from source. Run after editing the renderer at
  `packages/SynnapseKit/Sources/Tools/IconRenderer.swift`.

See `scripts/README.md` for the one-time credential setup (notarytool
keychain profile, App Store Connect API key) and a list of env vars
the CI tagged-release workflow reads.

## Milestone state

- M1 — Foundation (Networking, Auth, DesignSystem, app shells, CI). Done.
- M2 — Spotlight on macOS (global hotkey, panel, search). Done.
- M3 — Sign in with Apple end-to-end. Done.
- M4 — Approvals (flat + tree). Done.
- M5 — Finance (Personal, Accounts, Transactions, Investments). Done.
- M6 — Life terminal (Metal shader + Canvas fallback). Done.
- M7 — People + Inbox (read-only surfaces). Done.
- M8 — Advisors + Octagon + Trading Desk. Done.
- M9 — Sequences + Settings + accessibility polish. Done.
- M10 — Release engineering (icons, signing, scripts, tagged-release CI). Done.

## Conventions

- Swift 6, strict concurrency. All shared DTOs `Sendable`. Views `@MainActor`.
- No force-unwraps, no force-casts. Use `guard`, `throws`, `try #require`.
- Tests are written before implementation when feasible.
- Comments answer "why", not "what". Changelog comments are forbidden.
- Money values are `Decimal` end-to-end. JSON numbers are bridged via
  `String` so floating-point precision can't leak through the wire.
