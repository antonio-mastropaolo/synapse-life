# Synnapse — agent instructions

This file briefs Claude Code (and any AI collaborator) on how to work in this
repository. Read it before editing.

## Project

Synnapse is the native iOS + macOS reframe of Synapse v2 (the web app at
`/Users/amastro/Projects/synapse-v2`). Synapse v2 stays canonical for product
behavior. Synnapse re-implements it using SwiftUI, SwiftData, and `URLSession`
— no `WKWebView` wrappers, no React Native, no Capacitor. The native idiom
wins on every surface.

## Hard rules

1. **Swift 6, strict concurrency.** All shared DTOs are `Sendable`. Views are
   `@MainActor`. Actor boundaries are explicit and justified.
2. **No force-unwraps. No force-casts.** Use `guard`, `throws`, `try #require`
   in tests. The lint config enforces this.
3. **Test-first when adding behavior.** Write or extend tests before the
   implementation. The package's `swift test` is the load-bearing gate.
4. **No emojis** in code, comments, commit messages, or docs.
5. **No changelog-in-comments.** Comments answer "why", not "what just
   changed". Phrases like `// removed`, `// added for X`, `// previously`
   are forbidden.
6. **Do not wrap web views.** If a feature seems hard to native-port, file a
   note and discuss — do not reach for `WKWebView` as a shortcut.

## Tooling

- `xcodegen generate` regenerates `Synnapse.xcodeproj` from `project.yml`. The
  `.xcodeproj` is checked in for convenience; if you change `project.yml`,
  regenerate and commit both.
- `swift test --package-path packages/SynnapseKit` runs the package tests.
- `swiftformat .` and `swiftlint` enforce style; see `.swiftformat` and
  `.swiftlint.yml`.

## Module boundaries

- `Networking` owns transport. It does not know about persistence or UI.
- `Auth` owns the keychain. It does not call the network.
- `DesignSystem` is pure — no networking, no persistence. Identity tokens are
  per-identity, per-scheme.
- `Models` is the only module other modules are allowed to import as a
  dependency.

## Translation references

When translating a Synapse v2 web feature, follow this order:

1. Read the v2 source at `/Users/amastro/Projects/synapse-v2/<area>/`. Identify
   the framework (React/Next/etc.), state shape, routes, API surface, and
   visual language.
2. Decide the native idiom per platform: iPhone, iPad regular, Mac. Do not
   port literally — translate intent.
3. Land the change behind tests where it makes sense.

## When in doubt

Default to the Human Interface Guidelines, then to whatever Synapse v2 already
encoded as user-visible behavior. Disagreement with either is fine — just
write down why.

## Session handoff

Substrate work (persistence, account aggregation, AI agent layer) is tracked
separately from the surface-layer M-numbered milestones. The current state is
captured in `SUBSTRATE_INTEGRATION_MANIFEST.md` at the repo root. Read it
first if you're picking up a substrate task. The roadmap lives at
`~/.claude/plans/typed-rolling-koala.md`.

When fanning out parallel Swift work to subagents, use `mobile-app-builder`
or `general-purpose`. Do **not** use `ares-engineer` — it is scoped to the
two ARES repos and carries product-specific framing that does not belong
here.
