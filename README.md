# Synnapse

Native Apple-platform reframe of Synapse v2. iOS and macOS today; iPadOS, visionOS,
and watchOS deferred to later milestones.

## Layout

- `packages/SynnapseKit/` — shared Swift package. Modules:
  - `Models` — domain types (placeholder in M1).
  - `Networking` — `Endpoint`, `APIClient`, `URLProtocolStub` for tests.
  - `Auth` — `KeychainStore`.
  - `Persistence` — placeholder in M1.
  - `DesignSystem` — `Theme`, `Identity`, `Tokens`, `contrastRatio`.
- `apps/Synnapse-macOS/` — macOS app shell.
- `apps/Synnapse-iOS/` — iOS app shell.
- `apps/Shared/` — code shared between the two app targets.
- `project.yml` — xcodegen spec. Regenerate the Xcode project with `xcodegen generate`.

## Bootstrap

```
brew install xcodegen swiftlint swiftformat
xcodegen generate
```

## Test & build

```
swift test --package-path packages/SynnapseKit
xcodebuild -project Synnapse.xcodeproj -scheme SynnapseMac  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Synnapse.xcodeproj -scheme SynnapseiOS  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Milestone state

- M1 — Foundation. Networking, Auth, DesignSystem, app shells, CI. Done.
- M2 — Spotlight on macOS. Pending.

## Conventions

- Swift 6, strict concurrency. All shared DTOs `Sendable`. Views `@MainActor`.
- No force-unwraps, no force-casts. Use `guard`, `throws`, `try #require`.
- Tests are written before implementation when feasible.
- Comments answer "why", not "what". Changelog comments are forbidden.
