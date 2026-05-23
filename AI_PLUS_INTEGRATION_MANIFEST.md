# AI++ wedge integration manifest

This file is the contract between agent 5 (AI++ wedge) and the macOS / iOS app shells. Every surface listed below is built and tested inside `SynapseKit/Features`; the manifest tells the app layer where each surface needs to live in the navigation graph.

## 1. Weekly Digest

**Types**
- `Digest`, `DigestBullet`, `DigestBullet.Kind` (`Features/Digest/Digest.swift`)
- `DigestReducer` (`Features/Digest/DigestReducer.swift`)
- `DigestAPI` + `LiveDigestAPI` + `LocalStubDigestAPI` (`Features/Digest/DigestAPI.swift`)
- `DigestViewModel` (`Features/Digest/DigestViewModel.swift`)

**Routing**
- Dashboard / Personal pane: render the digest as a hero card above the recent transactions block. Use `DigestViewModel.refresh(accounts:transactions:)` on appear and on week-rollover.
- Future menu surface: `View → Weekly Digest` (macOS) / overflow on iOS.
- Tap a `DigestBullet` → host should jump to the cited transaction IDs. The bullet carries `[String]` of `Transaction.id`s in `citations`.

**Server route (forward-compat, not shipped yet)**
- `POST /api/ai/digest` returning the `Digest` envelope. `LiveDigestAPI(serverContractLive:)` flips to live once the route lands.

## 2. Forecast (cash-flow forward look)

**Types**
- `Forecast`, `ForecastPoint`, `PredictedCharge` (`Features/Forecast/Forecast.swift`)
- `ForecastReducer.project(...)`, `ForecastReducer.predictedRecurrings(...)` (`Features/Forecast/ForecastReducer.swift`)
- `ForecastAPI` + `LiveForecastAPI` + `LocalStubForecastAPI` (`Features/Forecast/ForecastAPI.swift`)
- `ForecastViewModel` (`Features/Forecast/ForecastViewModel.swift`)

**Routing**
- Net Worth chart on `FinancePersonalView`: extend the chart's series with `forecast.series` as a dashed projection. The `ForecastPoint.lowerBound` and `upperBound` define the shaded confidence band.
- "Predicted Sirius XM charge May 24: $37" rows: render `forecast.predictedCharges` as a list below the chart.
- "Your next 30 days of bills total $1,247": surface `forecast.nextThirtyDaysTotal` as a stat in the digest or as a Spotlight hit.
- Zero-crossing banner: when `forecast.zeroCrossing != nil`, paint the alert ribbon ("Checking may hit zero in N days").

**Server route (forward-compat)**
- `POST /api/ai/forecast` returning `Forecast`. Until shipped, the local reducer is authoritative.

## 3. Anomaly Explainer

**Types**
- `AnomalyExplanation`, `AnomalyExplanation.SuggestedAction` (`Features/AnomalyExplainer/AnomalyExplanation.swift`)
- `AnomalyExplainerReducer.explain(...)` (`Features/AnomalyExplainer/AnomalyExplainerReducer.swift`)
- `AnomalyExplainerAPI` + Live + Stub (`Features/AnomalyExplainer/AnomalyExplainerAPI.swift`)
- `AnomalyExplainerViewModel` (`Features/AnomalyExplainer/AnomalyExplainerViewModel.swift`)

**Routing**
- Every existing `InsightCard` with `kind == .anomaly` gains a `Why?` chip in its trailing edge. Tapping it opens a `.sheet` (iOS / iPad regular) / `NSWindow`-style sheet (macOS) hosting the explanation.
- The sheet body wires:
  - title = `explanation.title`
  - body  = `explanation.body` (2-3 sentences, deterministic)
  - citation chips = `explanation.citations` → tap routes to the corresponding `/transactions/{id}` deep link
  - bottom chips = `explanation.suggestedActions`: `markAsTransfer` routes to the transactions service, `investigate` opens the row in Transactions, `setAlertThreshold` opens Smart Alerts pre-filled with the row's category.

**Server route (forward-compat)**
- `POST /api/ai/explain` returning `AnomalyExplanation`. Local reducer is authoritative until then.

## 4. Smart Alerts

**Types**
- `AlertRule`, `AlertRule.Kind`, `FiredAlert`, `AlertsSnapshot` (`Features/SmartAlerts/SmartAlerts.swift`)
- `SmartAlertsEngine.evaluate(...)`, `SmartAlertsEngine.suggestRules(...)` (`Features/SmartAlerts/SmartAlertsEngine.swift`)
- `SmartAlertsViewModel` (`Features/SmartAlerts/SmartAlertsViewModel.swift`)

**Routing**
- New top-level surface: `SmartAlertsScene`.
  - Sidebar entry on macOS (between `Goals` and `Recurrings`): "Smart Alerts".
  - Tab on iOS overflow menu.
  - Deep link: `synapse://smart-alerts`.
- Scene structure:
  - Top section: installed rules with toggle for `enabled`.
  - Middle section: AI-suggested rules (chips). Tap accept = `vm.add(rule)`.
  - Bottom section: recent fired alerts. Tap a fired alert with `subjectId` → jump to that transaction or account.
- Three rule kinds today: `.balanceLow`, `.newRecurring`, `.unusualSpend`. All three are wired into `SmartAlertsEngine.evaluate`.

**Persistence**
- Local-only today (in-memory in `SmartAlertsViewModel`). Future: ship rules to the server.

## 5. Natural-language Ask bar (extended)

**Types**
- `AskCitation`, `AskCitationsExtractor` (`Features/AI/Intelligence/AskCitations.swift`)
- `IntelligenceAskViewModel` (`Features/AI/Intelligence/IntelligenceAskViewModel.swift`)

**Routing**
- `⌘K` already opens the existing `CommandBarViewModel`. The macOS shell may either:
  - (a) keep the existing command-bar (palette + suggestions + streaming answer), or
  - (b) wire the new `IntelligenceAskViewModel` for a dedicated Ask sheet with rich answer rendering (route label + citation chips).
- When an `AskCitation` chip is tapped, route by `kind`:
  - `.transaction` → `synapse://transactions/{targetId}`
  - `.account`     → `synapse://accounts/{targetId}`
  - `.category`    → `synapse://categories/{targetId}`
  - `.insight`     → `synapse://insights/{targetId}`
- Streaming token rendering and saved queries remain identical to the current command bar.

## 6. Apple Intelligence routing

**Types**
- `IntelligenceRoute`, `IntelligenceDelta`, `IntelligenceRouter` protocol (`Features/AI/Intelligence/IntelligenceRouter.swift`)
- `DefaultIntelligenceRouter` (picks route at construction time)
- `AppleIntelligenceRouter` (placeholder — wraps an underlying router until the `FoundationModels` framework is generally importable)
- `ServerIntelligenceRouter` (adapts any existing `AskAPI` to the `IntelligenceRouter` shape)

**Routing**
- `IntelligenceAskViewModel.route` is `.appleIntelligence` on macOS 15 / iOS 18+ and `.server` otherwise.
- Host UI: paint a small route badge next to the Ask answer (`"On-device"` for Apple Intelligence, `"Server"` otherwise) so the operator knows where the answer came from.
- The host can override with `DefaultIntelligenceRouter(forceRoute:)` for QA.

## 7. Categorization with confidence + corrections

**Types**
- `ConfidenceLevel` (3-bar) + `CategoryGuess.confidenceLevel` (`Features/AI/CategorizationTraining.swift`)
- `CategorizationTraining` protocol — extends `CategorizationAPI` with `suggestions(for:top:)` and `recordCorrection(_:)`
- `CategoryCorrectionStore` actor (in-memory persistence)
- `RecordingCategorizationAPI` wrapper

**Routing**
- Transactions list row: when the AI-guessed category has `confidenceLevel != .high`, render the 3-bar indicator next to the pill (1 / 2 / 3 lit bars).
- On a tapped low-confidence row, show 2-3 alternative chips from `suggestions(for:)`. Accepting an alternative calls `recordCorrection(_:)`.
- Hosts wire `RecordingCategorizationAPI(inner: LocalStubCategorizationAPI(), store: sharedStore)` so corrections flow into one observable place.

## Net new routing destinations the app shell must register

- `synapse://digest` — Weekly Digest scene (when shown standalone)
- `synapse://forecast/{accountId}` — Forecast detail for a specific account
- `synapse://anomaly/{transactionId}/explain` — Anomaly explainer sheet
- `synapse://smart-alerts` — Smart Alerts scene
- `synapse://smart-alerts/new?category={categoryLabel}` — Pre-fill rule creation from an anomaly's "Set alert threshold" action
- `synapse://ask?prompt={urlencoded}` — Open the Ask sheet pre-filled (deep link from Spotlight integration on macOS)

## Demo data note

Every API in this wedge defaults to its `LocalStub` until the corresponding server route ships. The stubs are deterministic — given the same `(accounts, transactions)` snapshot + a pinned clock, the digest, forecast, anomaly explanation, and fired alerts are bit-identical. Demo recordings can safely depend on these outputs.
