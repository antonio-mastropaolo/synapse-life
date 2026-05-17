# Synapse vs Copilot — Gap analysis + plan to close it

Last updated: 2026-05-17. Audience: us.

## TL;DR

Copilot is the bar for native macOS+iOS personal-finance UX. Their app is polished, dense, fast, well-categorized. Their core moat: years of bank-link UX and a curated category-pill system that gives every transaction a glanceable identity. Their weakness: AI is shallow (auto-categorization is the only AI feature shipped today; no narrative, no projection, no scenario tools, no chat).

Synapse's wedge is **AI depth**. We match the visual quality and category surface, then go far beyond on intelligence. Price ($49.99/yr vs $99/yr) reinforces the wedge by removing the "premium tier" objection.

## What Copilot does well (the parity bar)

| Surface | Copilot today | Synapse today | Parity status |
|---|---|---|---|
| **Sidebar nav** | Dark left rail w/ Dashboard / Transactions / Goals / Cash flow / Accounts / Investments / Categories / Recurrings + MY ACCOUNTS tree below w/ balance | Same sidebar shape after Copilot integration; INTELLIGENCE section added below MY ACCOUNTS | **At parity** (and one section richer) |
| **Dashboard = review inbox** | Daily-grouped list of un-reviewed transactions with category pills + checkboxes + "Mark N as reviewed" | Same shape (DashboardView). 30 unreviewed demo entries. Inspector pane with Goals + Net this month. | **At parity** on structure; widget hero row pending (Agent — Dashboard Widgets) |
| **Category pill system** | 11 categories with deterministic colors, custom categories addable | 11 canonical CategoryIDs (#4CAF6B restaurants etc), `CategoryPill` component, `CategoryStore` for custom | **At parity** |
| **Auto-categorization** | Rules engine + ML model; user corrections train it | `CategoryRulesEngine` (regex tables) + `CategorizationTraining` recording corrections | **At parity** on rules; ML training feedback loop is local-stub until server endpoint |
| **Accounts** | List of accounts with balances and last-sync; click for detail | List w/ AI sync-health card; per-account detail pending (Agent — AccountDetail) | **Approaching parity** |
| **Transactions** | Big list w/ search, category filter chips, grouped by Card | Same: sectioned-by-card, chips, pending toggle, search | **At parity** |
| **Subscriptions** | Detected recurrings categorized as subs; monthly total; cancel instructions | `SubscriptionDetector` over real transactions, grid of detected subs, monthly total, cancel sheet | **At parity** |
| **Recurrings** | Detected bills (utilities, rent, etc) with detect/confirm/ignore lifecycle | `RecurringDetector` + 3-section view (Detected/Confirmed/Ignored) + status store | **At parity** |
| **Cash flow** | Income vs expense bars per month + category spend bars + budgets | `ComingSoonView` stub | **Behind** — agent 4 was cut from the parallel run |
| **Goals** | Savings goal cards w/ progress rings, target dates, monthly contributions | `ComingSoonView` stub | **Behind** — same as above |
| **Investments** | Holdings table + allocation + net worth chart | View exists w/ holdings + allocation donut; net worth chart pending in FinancePersonal hero | **Approaching parity** |
| **Net Worth chart** | Smooth line over time on the home screen | Not yet on home (only inside Forecast) | **Behind** |
| **Net worth history persistence** | Daily snapshots of every account balance, charted over months/years | None — we read the current balance via Plaid each refresh, no historical snapshot table | **Behind (server-side)** |
| **Search** | Global search across transactions, accounts, merchants | Per-surface search; no global yet | **Behind** |
| **iOS app** | 4-5 tab bottom nav, native lists, swipe actions, large titles | 5-tab bottom nav (Dashboard / Transactions / Cash flow / Investments / More) | **At parity** on structure |
| **Plaid Link UX** | In-app native Plaid Link sheet to add accounts | None — Synapse is read-only, the web app owns Plaid Link | **Intentional gap** (read-only native client) |
| **Onboarding** | Setup wizard: link bank, pick categories, set first goal | OnboardingWizard w/ local profile (3 steps, no bank link) | **Different by design** |
| **Notifications** | Daily/weekly digest emails + push for unusual spend | Smart Alerts engine local-stubbed; no push yet | **Behind** |
| **Web app** | None | None | **At parity** |
| **Apple Watch** | Watch app w/ today's spend, balance, recents | None | **Behind** |
| **Widgets (Home Screen / Lock Screen)** | Yes | None | **Behind** |

## Where Synapse already beats Copilot

Things we have today that Copilot does not:

1. **AI narrator on every surface** — Forecast narrator generates 2-3 sentence summaries explaining what the numbers mean. Copilot just shows numbers.
2. **Balance projection chart with zero-crossing markers** — visual projection of "you'll hit zero on May 18" with a real dashed-line forecast. Copilot does not project forward.
3. **Anomaly explainer** — tap an anomaly, AI explains why it's anomalous, cites the user's baseline, suggests an action. Copilot flags anomalies (sometimes) but doesn't explain.
4. **Natural-language ask bar (⌘K)** — IntelligenceAskViewModel with citation chips and streaming answers. Copilot has nothing like this.
5. **5-advisor chat system** — domain-specific advisors (Financial, Tax, Health, Life, Strategy) with streaming bubbles. Copilot has no chat.
6. **Weekly digest** — DigestReducer produces a 5-7 bullet narrative summary auto-generated each week. Copilot doesn't have one.
7. **Smart Alerts rules engine** — proactive rules (balance-low, new-recurring, unusual-spend) + AI-suggested rules. Copilot has fixed alert types.
8. **Apple Intelligence routing abstraction** — IntelligenceRouter chooses between on-device (Foundation Models) and cloud routing per query. Copilot is cloud-only.
9. **LIFE terminal** — daily life log w/ a Metal-shader amber phosphor terminal. Not a finance feature but a wedge in the personal-life-app positioning.
10. **5 financial advisors with personality** — vs Copilot's "Copilot AI" single chatbot persona.

## The remaining gap (what to close)

In priority order:

### P0 — Must close to be considered "at parity"
1. **Net worth chart on the home pane.** Copilot's home is dominated by a single beautiful net worth line. We have one in Forecast but not on Personal. **Effort: 1 agent, ~half day.** Reuse `MoneyLineChart`; needs a historical snapshot reducer over the last 90/365 days.
2. **Net worth history persistence.** Today balances are current-only. Without daily snapshots there's no real chart. **Effort: server-side; daily cron in synapse-v2 to snapshot account balances into a new `account_balance_history` table.** ~1 day.
3. **Cash Flow surface.** The `ComingSoonView` stub is the biggest visible "Coming soon" message. Copilot's Cash Flow is one of their best screens. **Effort: 1 agent, ~half day.** Income/expense bars + per-category spend list + budget progress.
4. **Goals surface.** Also `ComingSoonView` today. **Effort: 1 agent, ~half day.** Progress rings + ETA math + add/edit goals.
5. **Account detail view (clickable MY ACCOUNTS).** Already planned; agent ran but blocked. **Effort: re-execute the planned agent on usage reset, ~hour.**
6. **Merchant icons on every transaction row.** Already planned. **Effort: re-execute, ~hour.**

### P1 — Close after parity, push the AI lead
7. **Global natural-language search.** Today ⌘K opens Ask but doesn't span "find this specific transaction." Merge them: one box, ranks transactions + surfaces + savable queries. **Effort: 1 agent, ~half day.**
8. **AI categorization confidence + active learning.** Today categorization confidence shows but corrections feed a local-stub. Wire to a server endpoint that re-trains a per-user category model. **Effort: server-side, 1 day.**
9. **Inline transaction enrichment.** Tap any transaction → AI explains what merchant this is (NYTimes = subscription, FOSTER ECOM = e-commerce wholesaler), where it fits in your patterns, whether it's expected. **Effort: 1 agent + server endpoint, ~1 day.**
10. **Push notifications wired to Smart Alerts.** Today alerts only render in-app. Add APNs + macOS Notification Center delivery via the SmartAlertsEngine. **Effort: 1 agent, ~half day.**

### P2 — Differentiate further
11. **Apple Watch app** — `today's spend / current balance / next bill` glance + complication. **Effort: 1 agent, 1 day.**
12. **Widgets** — Home Screen (iOS) + Notification Center (macOS) widgets for Net Worth, Today's Spend, Next Bill, Forecast. **Effort: 1 agent, 1 day.**
13. **Voice journal entries to LIFE.** Whisper transcription via on-device speech recognition (iOS 18+). **Effort: 1 agent, ~half day.**
14. **Predictive bill negotiation.** AI scans for cancelable / negotiable subscriptions, drafts cancellation/negotiation emails. **Effort: server-side endpoint + 1 agent, 1 day.**
15. **Multi-user / household mode.** Share a `LocalProfile`-equivalent for couples, surface joint vs personal spend separately. **Effort: 2 days.**
16. **CloudKit sync** — sync `LocalProfile` + saved Ask queries + Smart Alert rules + journal entries across user's Macs/iPhones/iPad. **Effort: 1 agent, ~1 day.**

### P3 — Marketing wedges (not features but differentiators)
17. **Pricing page that names Copilot.** Side-by-side comparison: "Synapse $49.99/yr vs Copilot $99.99/yr. AI features included by default, not paywalled."
18. **AI demo videos.** Record the Ask bar in action, the Anomaly Explainer, the Weekly Digest, the LIFE phosphor terminal.
19. **Refund-for-Copilot-receipt offer.** Users send a screenshot of their Copilot receipt → 50% off year-one of Synapse on top of our already-half-price.

## Sequencing — next 3 weeks

**Week 1 (post-usage-reset):** P0 #1-6. Closes visible parity gaps. ~5 agents total, sequential through worktree integration.

**Week 2:** P1 #7-10. Push AI lead beyond what Copilot has.

**Week 3:** Marketing wedges (P3) + P2 #11/12 (Apple Watch + Widgets — both unlock visible Apple-ecosystem-native moments Copilot doesn't have today).

## Risks

1. **Plaid sync errors.** The Credit One sync is failing today (`lastSyncError: INTERNAL_SERVER_ERROR`). Until synapse-v2 fixes that, users see real data only for the accounts that sync. Inspector banner is wired but the underlying fix is server-side.
2. **Apple Intelligence availability.** `FoundationModels` requires macOS 15+ / iOS 18+. Older OS users get cloud routing only. Document this in onboarding.
3. **Cost.** Every AI feature uses tokens. If we ship aggressive narrator + digest + ask + anomaly explainer, costs scale per-user. Need a per-user monthly token budget surfaced in Settings (today: not built).
4. **Apple App Store review.** Sign in with Apple is currently dropped in favor of local profile — Apple's review guidelines require SIWA as an option when ANY third-party login is offered. Today we offer no third-party login (just local profile), so we're compliant — but the moment we add CloudKit/iCloud or Google login, SIWA must come back as an option.
