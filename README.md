# Synapse

Native macOS and iOS personal-finance, life-log, and financial-advisors
app. Private life only — work surfaces (research, approvals, work
email, vendor intel) live in the [synapse-v2](https://github.com/antonio-mastropaolo/synapse-v2)
web app and were intentionally cut from Synapse on 2026-05-17.

The Xcode workspace, target, scheme, and Swift package names still carry
the `Synapse` spelling — that's the internal codename and renaming it
would churn the build graph for no user-visible benefit. The display
name (`CFBundleDisplayName`) is `Synapse`.

The client talks to the synapse-v2 server over HTTP; the Cockpit Dense
identity (deep black + amber-phosphor cues) is the default visual
language. Sign in with Apple is the only supported auth path.

## Surface scope

Four surviving surfaces:

- **Finance** — Personal, Accounts, Transactions, Investments.
- **Life** — Amber-Phosphor terminal log.
- **Advisors** — financial advisors, streaming chat.
- **Settings** — endpoint, conceal balances, reduce motion, sign-out.

## Layout

- `packages/SynapseLifeKit/` — shared Swift package. Modules:
  - `Models` — Sendable domain types, money primitives, shared JSON decoders.
  - `Networking` — `APIClient`, `Endpoint`, typed live API clients.
  - `Auth` — `KeychainStore`, `SessionStore`, Sign in with Apple bridge.
  - `Persistence` — local stores.
  - `DesignSystem` — `Theme`, `Identity`, `Tokens`, `contrastRatio`, `CockpitShellPreview`.
  - `SynapseCharts` — chart primitives for the Finance surfaces.
  - `Features` — view models + views (Finance, Life, Advisors, Settings, Auth).
  - `AppLifecycle` — `AppCore` (cross-platform construction seam), `DeepLink`, `RestorationPayload`, `AppLifecycleService`.
  - `Tools` — `IconRenderer` for the app icon (macOS-only target).
- `apps/Synapse-macOS/` — macOS app shell. Multi-window via SwiftUI `WindowGroup`.
- `apps/Synapse-iOS/` — iOS app shell. Four-tab `TabView` (Finance, Life, Advisors, More).
- `apps/Shared/` — code shared between the two app targets.
- `project.yml` — xcodegen spec. Regenerate the Xcode project with `xcodegen generate`.
- `scripts/` — `make-icons.swift`, `release-macos.sh`, `release-ios.sh`. See `scripts/README.md`.

## Build

```
brew install xcodegen
xcodegen generate
open SynapseLife.xcworkspace
```

Pick the `SynapseLifeMac` or `SynapseLifeiOS` scheme. The default base URL
is `http://localhost:3000/`; override with the `SYNAPSE_API_BASE`
environment variable on the scheme.

## Test

```
swift test --package-path packages/SynapseLifeKit
```

Snapshot references live under `packages/SynapseLifeKit/Tests/SnapshotTests/__Snapshots__/`.
Per-surface snapshots are split into mac and iOS variants; the test
runner records new references when missing rather than failing, so
the first run on a new platform produces baseline images.

## Release

The signing infrastructure is wired up; actual archival is left to
the operator because it requires Apple Developer credentials.

- `./scripts/release-macos.sh` — archives, exports, notarises, and
  staples the macOS app for Developer ID distribution.
- `./scripts/release-ios.sh` — archives, exports, and uploads the iOS
  app to TestFlight via `xcrun altool`.
- `./scripts/make-icons.swift` — re-renders the Cockpit-amber app
  icon set from source. Run after editing the renderer at
  `packages/SynapseLifeKit/Sources/Tools/IconRenderer.swift`.

See `scripts/README.md` for the one-time credential setup (notarytool
keychain profile, App Store Connect API key) and a list of env vars
the CI tagged-release workflow reads.

## Milestone state

- M1 — Foundation (Networking, Auth, DesignSystem, app shells, CI). Done.
- M3 — Sign in with Apple wiring. Client side complete; server
  `/api/auth/apple/exchange` route is not yet live, so unsigned local
  builds use the DEBUG-only "Continue without signing in" bypass on the
  SignInView to reach the surfaces.
- M5 — Finance (Personal, Accounts, Transactions, Investments). Done.
- M6 — Life terminal (Metal shader + Canvas fallback). Done.
- M8 — Advisors streaming chat. Done.
- M9 — Settings + accessibility polish. Done.
- M10 — Release engineering (icons, signing, scripts, tagged-release CI). Done.

Cockpit Dense shell from the integration commit is the app-wide chrome.

Milestones M2, M4, M7, and the Spotlight/Approvals/People/Inbox/
Sequences/Octagon/Trading-Desk halves of M3/M8/M9 originally shipped
in this repo (commits up to `e412731`) but were removed on
2026-05-17 when Synapse's scope was narrowed to private life only.
Their git history is preserved; they are not visible to the user in
the current build.

## Conventions

- Swift 6, strict concurrency. All shared DTOs `Sendable`. Views `@MainActor`.
- No force-unwraps, no force-casts. Use `guard`, `throws`, `try #require`.
- Tests are written before implementation when feasible.
- Comments answer "why", not "what". Changelog comments are forbidden.
- Money values are `Decimal` end-to-end. JSON numbers are bridged via
  `String` so floating-point precision can't leak through the wire.
