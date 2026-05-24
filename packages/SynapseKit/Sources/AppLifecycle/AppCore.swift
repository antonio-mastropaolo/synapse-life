import Foundation
import Observation
import SwiftData
import Models
import Networking
import Auth
import Features
import Persistence
import Intelligence

/// Cross-platform construction seam shared by the macOS and iOS app
/// shells. Both `SynapseMacApp.AppModel` and `SynapseiOSApp.AppModel`
/// build the same set of view models from the same `Networking`,
/// `Auth`, and `Features` types — `AppCore` lifts that wiring into the
/// package so the shells can be thin (just scenes + platform glue) and
/// so the wiring itself is testable from `swift test`.
///
/// Scope: Synapse is a private-life client. Work-flavoured surfaces
/// from the synapse-v2 web app (Spotlight, Approvals, People, Inbox,
/// Sequences, Octagon, Trading Desk) deliberately do not exist here.
/// The shells host Finance, Life, Advisors, and Settings only.
@MainActor
@Observable
public final class AppCore {

    public let baseURL: URL
    public let auth: AuthViewModel
    public let biometricGate: BiometricGate
    public let financePersonal: FinancePersonalViewModel
    public let financeAccounts: FinanceAccountsViewModel
    public let financeTransactions: FinanceTransactionsViewModel
    public let financeInvestments: FinanceInvestmentsViewModel
    /// Shared `FinanceAPI` handle so per-account drill-down screens (the iOS
    /// shell) can spin up their own scoped `FinanceTransactionsViewModel`
    /// without re-deriving which API (live vs mock) the app booted against.
    public let financeAPI: FinanceAPI
    public let lifeAPI: LifeAPI
    /// Activity surface. Composes a unified, glass-language feed from
    /// transactions, recurrings, proactive signals, and server-side digest
    /// entries. Replaces the legacy LIFE terminal surface.
    public let activity: ActivityViewModel
    public let advisors: AdvisorsListViewModel
    public let settings: SettingsViewModel

    // MARK: - Cockpit surfaces (lifted from the shell AppModels)

    /// Inbox of un-reviewed transactions. Seeded with the rich demo data so
    /// the Dashboard surface paints a believable queue on first launch.
    public let dashboard: DashboardViewModel
    /// Shared Categories VM — one instance survives sidebar selections; the
    /// demo / live transactions are projected through it once in `bootstrap`.
    public let categories: CategoriesViewModel
    public let digest: DigestViewModel
    public let forecast: ForecastViewModel
    public let smartAlerts: SmartAlertsViewModel
    public let intelligenceAsk: IntelligenceAskViewModel
    public let subscriptions: SubscriptionsViewModel
    public let memberships: MembershipsStore
    /// Recurrings surface. After each transaction refresh its detections are
    /// written through to `recurringStore`; on cold start the VM is hydrated
    /// back from that store so the surface is never empty.
    public let recurrings: RecurringsViewModel
    public let goals: GoalsStore
    /// Deep-link router + state restoration.
    public let lifecycle: AppLifecycleService

    /// Periodic background-refresh scheduler (Phase 4). The shell registers it
    /// once at launch via `registerBackgroundRefresh()`; the platform task runs
    /// `runScheduledRefresh()` and fires a local notification on new signals.
    public let backgroundRefresh = ProactiveRefreshScheduler()

    // MARK: - Substrate (Phase 1 persistence + Phase 3 intelligence)

    /// The SwiftData container the persistence stores read/write through.
    /// Demo / test wiring uses an in-memory store; live wiring targets the
    /// App Group container (falling back to the documents directory when the
    /// entitlement isn't available — see `PersistenceContainerFactory`).
    public let modelContainer: ModelContainer
    public let accountStore: AccountStore
    public let transactionStore: TransactionStore
    public let investmentStore: InvestmentStore
    public let auditLog: AuditLogStore
    /// Durable proactive feed (Phase 4). The analyzer's nightly pass upserts
    /// into this; the Dashboard inbox reads `recent()` from it.
    public let notifications: ProactiveNotificationStore
    /// Detected recurring charges (Phase 3 — G3). The detector re-derivation
    /// upserts into this; the agent's `get_recurrings` tool reads from it.
    public let recurringStore: RecurringStore

    /// Hybrid LLM router (Phase 3). Local on-device path + redacted remote
    /// path. Its LLM clients currently throw `notImplemented` and the router
    /// falls back to a deterministic stub, so it's safe to construct and call
    /// before the real backends land.
    public let llmRouter: LLMRouter

    /// When true, the VMs were wired to the Mock APIs and the demo
    /// fixtures should be seeded before the scene refreshes. DEBUG
    /// builds set this so the cockpit boots with representative data
    /// instead of the empty `.idle` state a Live API would yield while
    /// `synapse-v2` is offline.
    public let usesDemoData: Bool

    /// References to the Mock APIs when `usesDemoData == true`. The
    /// shell uses these handles in `bootstrap()` to call `DemoData.seed`
    /// before refreshing each VM. `nil` in release wiring.
    public let demoFinanceAPI: MockFinanceAPI?
    public let demoLifeAPI: MockLifeAPI?
    public let demoAdvisorsAPI: MockAdvisorsAPI?

    /// Surfaced for [[CrashFreeLaunchTests]] — set to `true` only if a
    /// future edit introduces a `Task.detached` somewhere in `init`.
    /// Today: no detached work is needed before the scene mounts; all
    /// async bootstrap is folded into `bootstrap()` which the shell
    /// awaits from `.task`.
    public let usedDetachedTaskDuringInit: Bool = false

    public init(baseURLOverride: String? = nil, useDemoData: Bool = false) {
        let envBase = ProcessInfo.processInfo.environment["SYNAPSE_API_BASE"]
        let raw = baseURLOverride ?? envBase ?? "http://localhost:3000/"
        // Two-step parse: try the caller-supplied value first, then
        // fall back to the documented default. The fallback is what
        // keeps offline / malformed-env launches from trapping.
        // `URL(string:)` is permissive enough that "::not a url::"
        // parses without throwing, so we additionally require an
        // `http(s)` scheme and a non-empty host before we accept the
        // user-supplied value.
        let parsedURL: URL? = {
            guard let u = URL(string: raw) else { return nil }
            guard let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https"
            else { return nil }
            guard let host = u.host, !host.isEmpty else { return nil }
            return u
        }()
        let fallback = URL(string: "http://localhost:3000/")
            ?? URL(fileURLWithPath: "/")
        self.baseURL = parsedURL ?? fallback

        let store = SessionStore()
        let sessionAPI = LiveSessionAPI(
            baseURL: baseURL,
            session: .shared,
            serverContractLive: false
        )
        self.auth = AuthViewModel(api: sessionAPI, store: store)
        // Demo wiring leaves the gate at `.unavailable` so the cockpit
        // boots straight into the seeded fixtures; production wiring
        // starts `.locked` and the shell calls `authenticate()` from
        // its first `.task`.
        self.biometricGate = useDemoData
            ? BiometricGate.alwaysUnlocked()
            : BiometricGate()

        let client = APIClient(
            baseURL: baseURL,
            session: .shared,
            defaultHeaders: ["Accept": "application/json"]
        )

        // Wire either Live or Mock APIs depending on the caller. Mock
        // wiring is what makes a DEBUG launch render demo fixtures
        // instead of an empty `.idle` state pointing at an offline
        // `synapse-v2` server. The Live path is unchanged.
        let financeAPI: FinanceAPI
        let lifeAPIWire: LifeAPI
        let advisorsAPIWire: AdvisorsAPI
        if useDemoData {
            let mockFinance = MockFinanceAPI()
            let mockLife = MockLifeAPI()
            let mockAdvisors = MockAdvisorsAPI()
            self.demoFinanceAPI = mockFinance
            self.demoLifeAPI = mockLife
            self.demoAdvisorsAPI = mockAdvisors
            financeAPI = mockFinance
            lifeAPIWire = mockLife
            advisorsAPIWire = mockAdvisors
        } else {
            self.demoFinanceAPI = nil
            self.demoLifeAPI = nil
            self.demoAdvisorsAPI = nil
            financeAPI = LiveFinanceAPI(client: client)
            lifeAPIWire = LiveLifeAPI(client: client, serverContractLive: false)
            advisorsAPIWire = LiveAdvisorsAPI(client: client)
        }
        self.usesDemoData = useDemoData

        self.financeAPI = financeAPI
        self.financePersonal = FinancePersonalViewModel(api: financeAPI)
        self.financeAccounts = FinanceAccountsViewModel(api: financeAPI)
        self.financeTransactions = FinanceTransactionsViewModel(api: financeAPI, accountId: nil)
        self.financeInvestments = FinanceInvestmentsViewModel(api: financeAPI)

        self.lifeAPI = lifeAPIWire

        self.advisors = AdvisorsListViewModel(api: advisorsAPIWire)

        self.settings = SettingsViewModel(store: UserDefaultsSettingsStore())

        // Persistence substrate. Demo / test wiring uses an in-memory store;
        // live wiring targets the App Group container. The container is
        // essential, so construction never silently degrades to "no store" —
        // it falls back to ephemeral and, only if even that fails, traps with
        // a clear message (matching `PersistenceContainerFactory`'s contract).
        let container = Self.makeModelContainer(useDemoData: useDemoData)
        self.modelContainer = container
        self.accountStore = AccountStore(modelContainer: container)
        self.transactionStore = TransactionStore(modelContainer: container)
        self.investmentStore = InvestmentStore(modelContainer: container)
        self.auditLog = AuditLogStore(modelContainer: container)
        self.notifications = ProactiveNotificationStore(modelContainer: container)
        self.recurringStore = RecurringStore(modelContainer: container)

        // Hybrid LLM router. Backends are Phase 3 shells today; the router
        // falls back to a deterministic stub so callers never break.
        self.llmRouter = LLMRouter(
            local: AppleFoundationLLM(),
            remote: RemoteLLM(client: client),
            redactor: PIIRedactor()
        )

        // Cockpit surfaces. The Dashboard inbox seeds from demo data so the
        // detail pane paints a populated queue on first run; the AI++ wedge
        // VMs defer to local stub reducers until the matching server route
        // lands and are refreshed from `bootstrap()` once the finance
        // snapshot exists.
        self.dashboard = DashboardViewModel(
            entries: DashboardDemoData.entries(
                relativeTo: Date(),
                calendar: Calendar.current
            ),
            ledgerTotal: DashboardDemoData.ledgerTotal,
            calendar: Calendar.current,
            referenceDate: Date(),
            locale: .current
        )
        self.categories = CategoriesViewModel(store: CategoryStore())
        self.digest = DigestViewModel(api: LocalStubDigestAPI())
        self.forecast = ForecastViewModel(api: LocalStubForecastAPI())
        self.smartAlerts = SmartAlertsViewModel()
        self.subscriptions = SubscriptionsViewModel()
        self.recurrings = RecurringsViewModel()
        self.memberships = MembershipsStore(usesSampleData: useDemoData)
        self.goals = GoalsStore(usesSampleData: useDemoData)

        let askAPI = LiveAskAPI(client: client, serverContractLive: false)
        let serverRouter = ServerIntelligenceRouter(askAPI: askAPI)
        let askRouter = DefaultIntelligenceRouter(
            appleIntelligence: AppleIntelligenceRouter(underlying: serverRouter),
            server: serverRouter
        )
        let personalForContext = financePersonal
        self.intelligenceAsk = IntelligenceAskViewModel(
            router: askRouter,
            contextProvider: {
                if case .ready(let snap) = personalForContext.state {
                    return AskContext(
                        accounts: snap.accounts,
                        recentTransactions: personalForContext.recentTransactions
                    )
                }
                return AskContext(accounts: [], recentTransactions: [])
            }
        )

        let financeTxnsVM = self.financeTransactions
        let recurringsVM = self.recurrings
        let dashboardVM = self.dashboard
        self.activity = ActivityViewModel(
            source: LiveActivitySource(
                lifeAPI: lifeAPIWire,
                transactions: { await MainActor.run { financeTxnsVM.rows } },
                recurrings: {
                    await MainActor.run {
                        recurringsVM.recurrings.map { $0.asRecurring() }
                    }
                },
                signals: { await MainActor.run { dashboardVM.proactiveSignals } }
            )
        )

        self.lifecycle = AppLifecycleService()
    }

    /// App Group used by the live persistence store, matching the bundle
    /// prefix (`tech.synapse.*`) the entitlements declare.
    private static let appGroupIdentifier = "group.tech.synapse"

    /// Build the SwiftData container without ever trapping on the expected
    /// failure modes. Demo wiring is in-memory; live wiring targets the App
    /// Group container (which itself falls back to the documents directory
    /// when the entitlement is absent — e.g. unsigned `swift test`). If the
    /// requested configuration fails, we retry ephemeral before giving up.
    private static func makeModelContainer(useDemoData: Bool) -> ModelContainer {
        let primary: PersistenceContainerFactory.Configuration = useDemoData
            ? .ephemeral
            : .live(appGroupIdentifier: appGroupIdentifier)
        if let container = try? PersistenceContainerFactory.make(primary) {
            return container
        }
        if let container = try? PersistenceContainerFactory.make(.ephemeral) {
            return container
        }
        // An environment where even an in-memory SwiftData store can't be
        // created is unrecoverable; surfacing it is more honest than running
        // against a phantom store.
        fatalError("Unable to create a SwiftData ModelContainer")
    }

    /// Async bootstrap the shell awaits from its first `.task`. Restores the
    /// auth session, seeds demo fixtures (when wired with Mock APIs), refreshes
    /// the finance VMs, projects Categories, and refreshes the cockpit
    /// surfaces. Recurrings is hydrated from the persisted store first (so the
    /// surface is never blank on a cold launch) and written back through after
    /// the live refresh recomputes it.
    public func bootstrap() async {
        await auth.restoreFromStore()
        if let finance = demoFinanceAPI,
           let life = demoLifeAPI,
           let advisorsAPI = demoAdvisorsAPI {
            await DemoData.seed(
                finance: finance,
                life: life,
                advisors: advisorsAPI
            )
        }

        // Cold-start read: paint last-known recurrings from the durable store
        // before the network refresh recomputes them.
        await hydrateRecurringsFromStore()

        await financePersonal.refresh()
        await financeAccounts.refresh()
        await financeTransactions.refresh()
        await financeInvestments.refresh()
        await activity.load()
        await advisors.refresh()

        // Project the dashboard's transactions through Categories so the
        // surface paints populated pill rows on first open.
        let dashboardTxs = dashboard.entries.map(\.transaction)
        await categories.project(transactions: dashboardTxs)

        refreshSurfaces()
        await persistRecurrings()
        await refreshProactiveFeed()
        applyConcealBalancesBridge()
    }

    /// Run the `ProactiveAnalyzer` against the current finance snapshot, persist
    /// the signals (dedup-on-id via the store), and load the durable feed into
    /// the Dashboard inbox. This is the foreground mirror of the nightly
    /// `BGTaskScheduler` pass; both write to the same store so the inbox shows
    /// the same set whether it was refreshed live or overnight. Store failures
    /// are swallowed so a transient write never breaks a launch.
    @discardableResult
    public func refreshProactiveFeed() async -> Int {
        guard case .ready(let snap) = financePersonal.state else { return 0 }
        let snapshot = AlertsSnapshot(
            accounts: snap.accounts,
            transactions: financePersonal.recentTransactions
        )
        let signals = ProactiveAnalyzer.analyze(snapshot: snapshot)
        let changed = (try? await notifications.upsertAll(signals)) ?? 0
        if let recent = try? await notifications.recent() {
            dashboard.setProactiveSignals(recent)
        }
        return changed
    }

    /// Background-refresh entry point shared by the iOS `BGTaskScheduler` task
    /// and the macOS `NSBackgroundActivityScheduler` activity. Re-runs the
    /// analyzer, persists the recurring detections, prunes aged notifications,
    /// and returns the count of new-or-changed signals so the caller can decide
    /// whether to fire a local notification. Pure store work — no UI assumptions
    /// beyond the `@MainActor` VMs it already owns.
    @discardableResult
    public func runScheduledRefresh() async -> Int {
        let changed = await refreshProactiveFeed()
        await persistRecurrings()
        try? await notifications.prune()
        return changed
    }

    /// Register the platform background-refresh task (idempotent). The handler
    /// runs `runScheduledRefresh()` and, when it surfaced new signals and the
    /// user has granted permission, posts a local notification. The shell calls
    /// this once at launch.
    public func registerBackgroundRefresh() {
        backgroundRefresh.register { [weak self] in
            guard let self else { return }
            let changed = await self.runScheduledRefresh()
            guard changed > 0 else { return }
            let state = await NotificationGate.shared.requestIfNeeded()
            if state == .granted {
                await NotificationGate.shared.postProactiveSummary(newCount: changed)
            }
        }
    }

    /// Dismiss one proactive signal: drop it from the surfaced feed immediately,
    /// then persist `setDismissed` so a re-run (foreground or nightly) never
    /// resurrects it. The store's `upsert` deliberately preserves `dismissed`.
    public func dismissSignal(id: String) async {
        dashboard.dismissProactiveSignal(id: id)
        _ = try? await notifications.setDismissed(id: id, true)
    }

    /// Refresh the AI++ wedge + detection surfaces against the current finance
    /// snapshot. Idempotent; safe to re-invoke on week-rollover / selection
    /// hooks. Mirrors what the macOS shell's `refreshIntelligenceSurfaces` did.
    public func refreshSurfaces() {
        guard case .ready(let snap) = financePersonal.state else { return }
        let tx = financePersonal.recentTransactions
        digest.refresh(accounts: snap.accounts, transactions: tx)
        forecast.refresh(accounts: snap.accounts, transactions: tx)
        smartAlerts.refresh(accounts: snap.accounts, transactions: tx)
        subscriptions.refresh(transactions: tx)
        recurrings.refresh(transactions: tx)
        memberships.refresh(transactions: tx)
        if goals.isEvaluationDue() {
            goals.evaluatePendingWindows(transactions: tx)
            if !goals.unseenResults.isEmpty {
                let hits = goals.unseenResults.filter { $0.outcome == .hit }.count
                let total = goals.unseenResults.count
                Task {
                    let state = await NotificationGate.shared.requestIfNeeded()
                    if state == .granted {
                        await NotificationGate.shared.postWeeklySummary(
                            hitCount: hits, totalCount: total
                        )
                    }
                }
            }
        }
    }

    /// Write the detector's current recurrings through to the durable store so
    /// the agent's `get_recurrings` tool and a future cold start see real data.
    /// Failures are swallowed: a transient store write must not break a launch.
    public func persistRecurrings() async {
        let rows = recurrings.recurrings.map { $0.asRecurring() }
        guard !rows.isEmpty else { return }
        _ = try? await recurringStore.upsertAll(rows)
    }

    /// Hydrate the Recurrings VM from the persisted store. No-op when the store
    /// is empty (first ever launch) — `RecurringsViewModel.hydrate` guards that.
    public func hydrateRecurringsFromStore() async {
        guard let rows = try? await recurringStore.all() else { return }
        recurrings.hydrate(rows.map { $0.asDetected() })
    }

    /// Mirror `settings.concealBalances` into the finance VM via the M5
    /// scene-phase path.
    public func applyConcealBalancesBridge() {
        if settings.concealBalances {
            financePersonal.scenePhaseDidChange(.inactive)
        }
    }
}
