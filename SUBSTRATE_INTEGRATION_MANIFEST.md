# Substrate Integration Manifest — Phase 0 + Phase 1 + Phase 2/3 scaffolds

Companion to the surface-layer manifests (`M7`, `M8`, `M9`, `AI_PLUS`,
`DASHBOARD`, `IOS`, `SHELL`). Those documented the polished UI surfaces.
This one documents the **substrate** the surfaces will eventually read
from: a SwiftData persistence layer, a Plaid-shaped account-aggregation
scaffold, and a hybrid LLM scaffold. Written so the next session can
continue cleanly after `/clear`.

The full plan with rationale lives at
`/Users/amastro/.claude/plans/typed-rolling-koala.md`. This manifest is
the **session-end snapshot**: what's done, where it lives, what's still
stub, and the exact next moves.

## Status

| Phase | Status | Test count this session |
|------|--------|------|
| Phase 0 — App Store unblockers | **complete** | KeychainStoreTests green |
| Phase 1 — SwiftData persistence | **complete** | 17 / 17 pass |
| Phase 2 — Plaid proxy connector (no LinkKit SDK) | **network layer live** | 18 / 18 pass |
| Phase 3 — Intelligence scaffold (no real LLM) | **scaffold only** | 37 / 37 pass |
| Phase 4 — Native sensors + agentic flows | **started: ProactiveAnalyzer** | 5 / 5 pass |
| Phase 5 — Monetization + observability + submission | not started | — |

**Overall: 72 / 72 substrate tests pass.** The G1 Decimal canary is now
fixed (see below). (Full repo `swift test` still shows pre-existing macOS
snapshot-rendering mismatches in the Dashboard view suites; those are
host-environment baselines, unrelated to substrate.)

## What landed (file-level)

### Phase 0 — App Store unblockers

- `apps/Synnapse-iOS/PrivacyInfo.xcprivacy` — new. Declares financial-info
  + identifier + email + name + crash-data collection; declares required-
  reason API uses for `UserDefaults`, `FileTimestamp`, `SystemBootTime`,
  `DiskSpace`.
- `apps/Synnapse-macOS/PrivacyInfo.xcprivacy` — new. Same categories
  minus device-id (sandbox restricts the API).
- `apps/Synnapse-iOS/Synnapse-iOS.entitlements` — added
  `aps-environment=development`, `usernotifications.communication`,
  renamed App Group to `group.tech.synnapse` so it matches the bundle
  prefix `tech.synnapse.ios`.
- `apps/Synnapse-macOS/Synnapse-macOS.entitlements` — App Group renamed
  to `group.tech.synnapse` to match the iOS target.
- `packages/SynnapseKit/Sources/Auth/KeychainStore.swift` — default
  accessibility class tightened to
  `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`. New `accessibility:`
  init parameter so tests can opt into the relaxed class without
  mutating global state. The legacy static
  `KeychainStore.accessibilityClass` is kept as an alias of the new
  `defaultAccessibility` for backwards compat.
- `packages/SynnapseKit/Sources/Auth/BiometricGate.swift` — new.
  `@MainActor @Observable` Face-ID / device-passcode gate via
  `LocalAuthentication`. 60-second background-lock threshold (configurable).
  `noteBackgrounded()` / `noteForegrounded()` / `lock()` / `authenticate(reason:)`
  / `alwaysUnlocked()`.
- `packages/SynnapseKit/Sources/AppLifecycle/AppCore.swift` — adds
  `public let biometricGate: BiometricGate`. Demo wiring uses
  `BiometricGate.alwaysUnlocked()`; live wiring starts `.locked`.
- `packages/SynnapseKit/Tests/AuthTests/KeychainStoreTests.swift` —
  updated to assert the new strong default, the alias, and the test
  helper that opts into the relaxed class.

### Phase 1 — SwiftData persistence

Replaces the empty `Sources/Persistence/Placeholder.swift` (deleted) with:

- `Sources/Persistence/Module.swift` — module marker + schema version
  string (`"1.0.0"`).
- `Sources/Persistence/ContainerFactory.swift` — `PersistenceContainerFactory`
  with `.live(appGroupIdentifier:)` / `.ephemeral` / `.namedFile(URL)`
  configurations. Live falls back to the documents directory when the
  App Group isn't entitled (so unsigned `swift test` and dev simulator
  runs still get a store).
- `Sources/Persistence/Projections.swift` — DTO ↔ persisted
  conversions. `from(_:syncedAt:)`, `toDTO()`, and `update(from:syncedAt:) -> Bool`
  for each persisted type. The `update` return value (true when any
  field changed) is what the store actors use to decide whether to
  emit a `NotificationCenter` change event.
- `Sources/Persistence/Models/PersistedFinanceAccount.swift` — `@Model`
  mirror of `FinanceAccount`. Stores `kindRaw: String`; `kind` is a
  computed projection that falls through to `.other` on unknown
  raw values (forward-compat with future taxonomy additions).
- `Sources/Persistence/Models/PersistedTransaction.swift` — `@Model`
  mirror of `Transaction`. Stores `categoryRaw: String?`; `category`
  is the projected `TransactionCategory`.
- `Sources/Persistence/Models/PersistedInvestmentPosition.swift` —
  `@Model` mirror of `InvestmentPosition`. Synthesizes the composite
  id `"\(accountId):\(securityId)"` as the `.unique` attribute.
- `Sources/Persistence/Models/PersistedAuditLog.swift` — `@Model` for
  the append-only event store. Companion enums `AuditEventKind` (raw
  strings `pii.read`, `plaid.link`, `txn.sync`, `llm.call`,
  `money.move`, `auth`) and `AuditOutcome` (`ok`, `denied`, `error`,
  `cancelled`).
- `Sources/Persistence/Stores/AccountStore.swift` — `@ModelActor`. All
  methods take/return Sendable DTOs. `upsert(_:syncedAt:)`,
  `upsertAll(_:syncedAt:)`, `all(institutionId:)`, `get(id:)`,
  `count()`, `deleteAll()`. The persisted reference type never crosses
  the actor boundary.
- `Sources/Persistence/Stores/TransactionStore.swift` — `@ModelActor`.
  `upsert`, `upsertAll`, `delete(ids:)` (Plaid removed-array path),
  `deleteAll`, `all(limit:)`, `forAccount(_:limit:)`, `between(_:and:category:limit:)`,
  `get(id:)`, `count()`, `seedIfEmpty(_:)`.
- `Sources/Persistence/Stores/InvestmentStore.swift` — `@ModelActor`.
  `upsert`, `upsertAll`, `all()`, `forAccount(_:)`, `count()`,
  `deleteAll()`.
- `Sources/Persistence/Stores/AuditLogStore.swift` — `@ModelActor`.
  `append(kind:subject:detail:outcome:timestamp:)`, `recent(limit:)`,
  `count()`, `prune(olderThan:now:)`. The companion `AuditLogEntry`
  Sendable struct crosses the actor boundary (carries `kind: AuditEventKind?`
  which is `nil` when the raw string is unknown to this binary).

### Phase 2 — Plaid scaffold (NO real SDK linked)

- `Sources/Connectors/Plaid/PlaidConnector.swift` — `public protocol PlaidConnector: Sendable`.
  Six `async throws` methods: `createLinkToken(userId:)`,
  `exchangePublicToken(_:)`, `syncTransactions(itemId:cursor:)`,
  `fetchAccounts(itemId:)`, `fetchInvestments(itemId:)`,
  `removeItem(itemId:)`.
- `Sources/Connectors/Plaid/PlaidTypes.swift` — Sendable types:
  `PlaidLinkToken`, `PlaidItem` (with `accessTokenRef` = Keychain key,
  never the raw token), `PlaidSyncDelta` (added / modified / removedIds
  / nextCursor / hasMore), `PlaidEnvironment` enum (`.sandbox`,
  `.development`, `.production`) with matching base URLs.
- `Sources/Connectors/Plaid/StubPlaidConnector.swift` — deterministic
  sandbox-shaped fixtures. 3 fake transactions on first sync, empty
  delta after. 1 checking + 1 credit account. AAPL + VOO positions.
- `Sources/Connectors/Plaid/LivePlaidConnector.swift` — `actor`
  pointing at the synapse-v2 server-side endpoints
  (`/api/connectors/plaid/...`). All six methods now make real
  `APIClient.send` POST calls, encode the request body as JSON, forward
  `X-Plaid-Environment`, decode the proxy envelope into native `Models`
  DTOs, and map `APIError` → `PlaidConnectorError`. The `notImplemented`
  case is no longer thrown by the live connector. (Updated this session.)
- `Sources/Connectors/Plaid/PlaidWire.swift` — new. Request bodies
  (`PlaidLinkTokenRequest` / `PlaidExchangeRequest` / `PlaidSyncRequest` /
  `PlaidItemRequest`) and response envelopes (`PlaidLinkTokenEnvelope`
  with dual epoch/ISO-8601 expiration decode, `PlaidItemEnvelope`,
  `PlaidSyncEnvelope`, `PlaidInvestmentsEnvelope` + `PlaidHoldingRow`,
  `PlaidOKEnvelope`). Decoding reuses the native `ServerTransactionRow` /
  `FinanceAccountsResponse` so the Plaid path projects identically to the
  legacy `/api/finance/*` path.
- `Tests/ConnectorsTests/LivePlaidConnectorTests.swift` — new. 9 tests
  over `URLProtocolStub`: per-method envelope decode + path/method
  assertions, dual expiration formats, signed-amount + removed-id
  projection, 503 → `.server(status:)`, malformed body → `.decoding`.
- `Sources/Connectors/Plaid/PlaidSync.swift` — `actor PlaidSync`.
  Wires `PlaidConnector` → `AccountStore` + `TransactionStore` +
  `InvestmentStore` + `AuditLogStore`. Cursor-paginates while
  `delta.hasMore`. Writes one `AuditLogStore` row on success or
  failure. Returns `PlaidSyncResult(addedCount, modifiedCount, removedCount, cursor)`.

### Phase 3 — Intelligence scaffold (NO real LLM linked)

- `Sources/Intelligence/Module.swift` — module marker + doc explaining
  the hybrid routing strategy and the PII redaction contract.
- `Sources/Intelligence/LLMClient.swift` — `protocol LLMClient: Sendable`.
  Sendable types: `LLMPrompt`, `LLMTool` (JSON-Schema arg shape),
  `LLMResponse`, `LLMDelta`, `LLMError`.
- `Sources/Intelligence/AppleFoundationLLM.swift` — `actor`. `name = "apple.foundation"`.
  `#if canImport(FoundationModels)` import is present; both `generate`
  and `stream` currently throw `LLMError.notImplemented`. A
  `// Phase 3 — call SystemLanguageModel.shared.respond(...)` comment
  marks the future implementation site.
- `Sources/Intelligence/RemoteLLM.swift` — `actor`. Configurable name
  (`"remote.claude"` / `"remote.gpt"`). Holds an `APIClient`. Documents
  the SSE frame shape (`data: {…}` text deltas + `done` terminator)
  matching `AdvisorsAPI`. Throws `notImplemented` until Phase 3 wires
  `POST /api/llm/proxy`.
- `Sources/Intelligence/StubLLM.swift` — `actor`. Deterministic stream
  that chunk-splits on whitespace and emits one `LLMDelta.text(...)`
  per chunk then `.done`. Used by tests and SwiftUI previews.
- `Sources/Intelligence/PIIRedactor.swift` — **the only real code in
  this module.** Strips emails (`<email>`), phones (`<phone>`), SSNs
  (`<ssn>`), accounts (8–17 digit runs), card numbers (→ `••••<last4>`),
  addresses (`<address>`), dollar amounts > $50,000 (exclusive, →
  `<large_amount>`). Whitelist parameter `allowedMerchants: Set<String>`.
  27 fixture tests pass.
- `Sources/Intelligence/LLMRouter.swift` — `actor LLMRouter` (renamed from
  `IntelligenceRouter` this session; see G2). Constructor
  `(local: LLMClient, remote: LLMClient, redactor: PIIRedactor)`. Single
  `route(_:tools:)` method: simple queries (`prompt.user.count < 200 && tools.count <= 2`) → local;
  complex → redact then remote. Falls back to a stub on `notImplemented`
  so the UI doesn't break in Phase 3 dev.
- `Sources/Intelligence/ToolCallRegistry.swift` — `actor`. Constructor
  takes `AccountStore`, `TransactionStore`, `InvestmentStore`,
  `AuditLogStore`. `static defaultTools()` returns four `LLMTool`
  descriptors (`get_accounts`, `get_transactions`, `get_investments`,
  `get_recurrings`). `dispatch(name:args:)` is wired for `get_accounts`
  + `get_transactions(start, end, category?)` returning JSON strings.
  `get_investments` and `get_recurrings` throw
  `LLMError.toolNotImplemented` — see "Known gaps" below.

### Phase 4 — Proactive insights engine (started this session)

The first Phase 4 unit — chosen because it's pure, on-device, and needs no
operator credentials (unlike receipt OCR / voice / App Intents, which need
app-target or platform-UI surfaces, and unlike Phase 5, which needs
third-party SDK accounts).

- `Sources/Features/Proactive/ProactiveSignal.swift` — new. Unified feed
  item the Dashboard inbox surfaces: `kind` (`.upcomingBill` /
  `.newRecurring` / `.anomalousSpend`), `headline` / `body`, `subjectId`
  (jump target), `date`, `severity` (`.info` / `.warning` / `.alert` with
  a `rank`). Stable `id` so a nightly re-run dedups against persisted rows.
- `Sources/Features/Proactive/ProactiveAnalyzer.swift` — new. Pure
  `enum` with `analyze(snapshot:configuration:) -> [ProactiveSignal]` over
  the existing `AlertsSnapshot`. Composes `ForecastReducer.predictedRecurrings`
  for bills (a new merchant → `.newRecurring`, a known merchant due within
  `lookaheadDays` → `.upcomingBill`; never both) and a fresh weekly z-score
  detector for `.anomalousSpend` (per-category current-week total vs a
  trailing-`historyWeeks` baseline; `z >= anomalyAlertZ` escalates to
  `.alert`; needs `minimumActiveWeeks` of history). Reuses the module's
  `formatCurrency` / `formatShortDate` / `absDecimal`.
- `Tests/FeaturesTests/Proactive/ProactiveAnalyzerTests.swift` — new, 5
  tests: known-recurring-due-soon → upcoming bill; unknown-recurring →
  new recurring (not both); current-week spike → alert anomaly; flat spend
  → no anomaly; deterministic ids + severity ranking + no dup ids.

**Phase 4 follow-on (not started):** persist signals as a `PersistedNotification`
`@Model` + store so they survive backgrounding (G4-adjacent), run the
analyzer from a nightly `BGTaskScheduler` task, and surface the feed in the
Dashboard inbox. Receipt OCR (VisionKit), voice (Speech), and App Intents
remain unstarted — all need app-target wiring.

### Package.swift

- New library products: `Connectors`, `Intelligence`.
- New targets matching the new source directories. Both depend on
  `Models` + `Networking` + `Persistence`.
- New test targets: `PersistenceTests`, `ConnectorsTests`,
  `IntelligenceTests`.

## Known gaps (start here next session)

### G1 — SwiftData `Decimal` precision — RESOLVED

Was: SwiftData routed `Decimal` through `Double` on the way to SQLite,
so `0.30000000000000004` read back as `0.3`.

**Fixed** by persisting money/quantity as canonical decimal Strings.
Each of `PersistedFinanceAccount` / `PersistedTransaction` /
`PersistedInvestmentPosition` now stores a `…Raw: String`/`String?`
backing and exposes the `Decimal`/`Decimal?` value through a computed
property (`Decimal.description` on write, `Decimal(string:)` on read) —
the same stored-raw + computed-projection pattern already used for
`kindRaw`/`categoryRaw`. `Projections.swift` and the store actors are
unchanged because they only touch the Decimal-typed API. `Models/*`
DTOs are untouched. One follow-on edit: `InvestmentStore.all()` /
`forAccount()` can no longer use `SortDescriptor(\.value)` (computed key
paths aren't SQL-mappable, and a String sort misorders magnitudes), so
they now sort the projected DTOs numerically in memory. The 20-fixture
canary `allFixturesRoundTripExactly` passes; PersistenceTests 17/17.

### G2 — Namespace collision: two `IntelligenceRouter`s — RESOLVED

The two types turned out to be different abstractions that merely shared
a name, not competing implementations:

- `Features.IntelligenceRouter` — Ask-UI streaming protocol
  (`stream(prompt:context:) -> AsyncThrowingStream<IntelligenceDelta>`),
  shipped + tested, drives the Ask bar via `IntelligenceAskViewModel`.
- `Intelligence.IntelligenceRouter` — LLM-level actor
  (`route(LLMPrompt, tools:) async -> LLMResponse`), substrate scaffold
  whose LLM clients still throw `notImplemented` (G6).

Deleting the Features one would have regressed the working Ask UI with no
functioning replacement (the substrate router can't stream and its
backends are stubs). **Resolved** by renaming the substrate actor to
`LLMRouter` (it routes between `LLMClient`s — honest naming), leaving the
Features Ask router untouched. The collision is gone and `AppCore` can
import both modules unqualified. The eventual delete-and-repoint of the
Features router onto `LLMRouter` is real Phase 3 work, gated on G6 (a live
LLM client + an Ask-shaped streaming bridge). IntelligenceTests 37/37.

### G3 — `RecurringStore` missing

`ToolCallRegistry.defaultTools()` registers `get_recurrings` but
`dispatch("get_recurrings", …)` throws `LLMError.toolNotImplemented`.
Adding it needs three steps: a `Recurring` Sendable DTO in `Models/`,
a `PersistedRecurring` `@Model` + projection, and a
`@ModelActor RecurringStore`. The `Features/Recurrings/` module
already infers recurring transactions in memory — that detector is
the seed for the persisted store.

### G4 — `AppCore` doesn't hold the new persistence stores or
`LLMRouter` yet

This session added `biometricGate` only. Next pass: build a
`ModelContainer` via `PersistenceContainerFactory.make(.live(...))`,
construct the four store actors against it, construct
`LLMRouter`, surface them as `public let ...` on `AppCore`,
and inject into the SwiftUI environment from `apps/Shared/RootView.swift`.
With G2 resolved, `AppLifecycle` can import both `Features` and
`Intelligence` without the name clash.

### G5 — Phase 2 LinkKit SDK + server routes not added

The iOS-side network layer is **done**: `LivePlaidConnector` makes real
`APIClient.send` calls against `/api/connectors/plaid/*` and is tested
against `URLProtocolStub`. Two things remain, both needing the operator:

1. **synapse-v2 server routes.** The six proxy endpoints don't exist yet
   server-side. The contract is pinned iOS-side (see `PlaidWire.swift`
   envelopes); the server must hold the Plaid `client_id` + `secret`,
   store access tokens in its own Keychain, and answer the six paths the
   connector calls (`link-token/create`, `item/public-token/exchange`,
   `transactions/sync`, `accounts/get`, `investments/get`, `item/remove`).
   Block on operator credentials before building these.
2. **LinkKit presentation.** `PlaidLinkController`
   (`UIViewControllerRepresentable`) to present Link and hand the
   one-shot `public_token` back to `exchangePublicToken`. Needs the Plaid
   LinkKit `.package(url:)` in `Package.swift`. The connector is ready to
   consume whatever LinkKit returns.

### G6 — Phase 3 real LLM calls not wired

`AppleFoundationLLM` and `RemoteLLM` both throw `notImplemented`.
Apple `FoundationModels` lands at iOS 18.1+; bump deployment target if
needed. `RemoteLLM` waits on a synapse-v2 `POST /api/llm/proxy`
endpoint that streams SSE in the same shape `AdvisorsAPI` already
parses.

## How to continue

1. Read this manifest. Skim the plan at
   `/Users/amastro/.claude/plans/typed-rolling-koala.md` for the
   rationale and the full 5-phase roadmap.
2. Decide priority:
   - **G1 (decimal-as-string)** — small, isolated, high-value test
     coverage. Good ~30-minute first move.
   - **G4 (AppCore wiring)** — unlocks all subsequent work. Medium
     scope; pairs well with G2 (namespace cleanup).
   - **G5 (real Plaid)** — needs operator credentials. Block on user
     before starting.
   - **G6 (real LLM)** — Apple FoundationModels can land without
     external creds; remote needs synapse-v2 endpoint first.
3. Use `mobile-app-builder` or `general-purpose` for parallel
   fan-outs. **Do not use `ares-engineer`** — it's scoped to the two
   ARES repos and carries product-specific framing that bleeds into
   the output.

## Test invocation

```bash
cd packages/SynnapseKit
swift build                                   # full graph, currently clean
swift test                                    # all suites, ~62/63 pass
swift test --filter PersistenceTests          # 16/17 pass (G1 canary)
swift test --filter ConnectorsTests           # 9/9
swift test --filter IntelligenceTests         # 37/37
swift test --filter AuthTests                 # all green
```
