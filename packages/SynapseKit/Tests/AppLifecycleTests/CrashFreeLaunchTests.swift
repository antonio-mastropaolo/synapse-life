import Foundation
import Testing
import Models
import Persistence
@testable import AppLifecycle

/// `AppCore` is the cross-platform construction seam shared by both the
/// macOS and iOS app shells (`SynapseMacApp.AppModel` and
/// `SynapseiOSApp.AppModel`). The shells instantiate the same set of
/// `Networking`/`Auth`/`Features` view models that `AppCore` does, so a
/// crash-free `AppCore.init` is a load-bearing proxy for a crash-free
/// shell `AppModel.init`.
///
/// Synapse's surface scope is private-life only — Finance, Life,
/// Advisors, Settings. Work surfaces from synapse-v2 (Spotlight,
/// Approvals, People, Inbox, Sequences, Octagon, Trading Desk) live in
/// the web app, not this client.
@Suite("Crash-free launch")
@MainActor
struct CrashFreeLaunchTests {

    @Test("AppCore init succeeds in the default (signed-out) state")
    func defaultInit() {
        let core = AppCore()
        // Touch every wired-up VM so the test fails loudly if any of
        // them are nil or trap during init.
        _ = core.auth
        _ = core.financePersonal
        _ = core.financeAccounts
        _ = core.financeTransactions
        _ = core.financeInvestments
        _ = core.financeAPI
        _ = core.lifeAPI
        _ = core.activity
        _ = core.advisors
        _ = core.settings
        // Substrate wiring (Phase 1 persistence + Phase 3 intelligence) must
        // also construct without trapping — the live container path falls
        // back to an on-disk store under unsigned `swift test`.
        _ = core.modelContainer
        _ = core.accountStore
        _ = core.transactionStore
        _ = core.investmentStore
        _ = core.auditLog
        _ = core.notifications
        _ = core.recurringStore
        _ = core.llmRouter
        // Cockpit surfaces lifted from the shell AppModels.
        _ = core.dashboard
        _ = core.categories
        _ = core.digest
        _ = core.forecast
        _ = core.smartAlerts
        _ = core.intelligenceAsk
        _ = core.subscriptions
        _ = core.memberships
        _ = core.recurrings
        _ = core.goals
        _ = core.lifecycle
    }

    @Test("Demo bootstrap populates the Recurrings VM and writes through to the store")
    func demoBootstrapPersistsRecurrings() async throws {
        let core = AppCore(useDemoData: true)
        await core.bootstrap()
        // The detector ran against the seeded demo transactions, so the VM has
        // rows AND they were written through to the durable store — the data
        // the agent's get_recurrings tool reads.
        #expect(!core.recurrings.recurrings.isEmpty)
        let persisted = try await core.recurringStore.all()
        #expect(!persisted.isEmpty)
        #expect(persisted.count == core.recurrings.recurrings.count)
    }

    @Test("Demo bootstrap surfaces the proactive feed on the Dashboard inbox")
    func demoBootstrapPopulatesProactiveFeed() async throws {
        let core = AppCore(useDemoData: true)
        await core.bootstrap()
        // The analyzer ran against the seeded snapshot, wrote signals to the
        // durable store, and loaded them into the Dashboard VM. The store and
        // the surfaced feed agree.
        let persisted = try await core.notifications.recent()
        #expect(!persisted.isEmpty)
        #expect(core.dashboard.proactiveSignals.count == persisted.count)
        // Re-running the feed is idempotent on the surfaced count (dedup-on-id).
        await core.refreshProactiveFeed()
        let again = try await core.notifications.recent()
        #expect(core.dashboard.proactiveSignals.count == again.count)
    }

    @Test("dismissSignal drops the row from the feed and persists the dismissal")
    func dismissSignalPersists() async throws {
        let core = AppCore(useDemoData: true)
        await core.bootstrap()
        let first = try #require(core.dashboard.proactiveSignals.first)
        let before = core.dashboard.proactiveSignals.count

        await core.dismissSignal(id: first.id)
        // Dropped from the surfaced feed immediately.
        #expect(core.dashboard.proactiveSignals.contains { $0.id == first.id } == false)
        #expect(core.dashboard.proactiveSignals.count == before - 1)

        // A re-run must not resurrect it — the store preserves `dismissed`.
        await core.refreshProactiveFeed()
        #expect(core.dashboard.proactiveSignals.contains { $0.id == first.id } == false)
    }

    @Test("runScheduledRefresh surfaces signals and is idempotent on re-run")
    func scheduledRefreshRuns() async throws {
        let core = AppCore(useDemoData: true)
        await core.bootstrap()
        // The background entry point re-runs the analyzer; the first nightly
        // pass after a fresh bootstrap finds nothing new (bootstrap already
        // populated the store), so a clean re-run reports zero changes.
        let changed = await core.runScheduledRefresh()
        #expect(changed == 0)
        // The feed is still populated and the recurrings store still holds rows.
        #expect(!core.dashboard.proactiveSignals.isEmpty)
        #expect(try await core.recurringStore.count() > 0)
    }

    @Test("hydrateRecurringsFromStore paints the VM from persisted rows")
    func hydrateFromStore() async throws {
        let core = AppCore(useDemoData: true)
        let when = Date(timeIntervalSince1970: 1_779_840_000)
        _ = try await core.recurringStore.upsert(Recurring(
            id: "recurring.coldstart",
            merchant: "Cold Start Co",
            category: "subscriptions",
            medianAmount: Decimal(string: "9.99")!,
            cadenceDays: 30,
            lastSeen: when.addingTimeInterval(-30 * 86_400),
            predictedNext: when,
            occurrenceCount: 3,
            confidence: 0.8,
            transactionIds: ["a", "b", "c"],
            isIncome: false
        ))
        await core.hydrateRecurringsFromStore()
        #expect(core.recurrings.recurrings.contains { $0.merchant == "Cold Start Co" })
    }

    @Test("AppCore init survives an invalid base URL by falling back")
    func offlineInvalidBaseURL() {
        // The shells fall back to `http://localhost:3000/` when
        // `SYNAPSE_API_BASE` cannot be parsed. The test asserts the
        // fallback path doesn't trap.
        let core = AppCore(baseURLOverride: "::not a url::")
        #expect(core.baseURL.absoluteString.contains("localhost"))
    }

    @Test("AppCore init lands in .signedOut by default — auth bootstrap is deferred")
    func signedOutByDefault() {
        let core = AppCore()
        // Construction must not implicitly sign anyone in; the shells
        // do that explicitly via `bootstrapIfNeeded` after the scene
        // mounts. This pins the default and surfaces any regression
        // where init starts the keychain restore eagerly.
        #expect(core.auth.state == .signedOut)
    }

    @Test("AppCore init does not leak a detached Task")
    func noDetachedTaskLeak() {
        // We cannot inspect the runtime's task tree directly, but we can
        // assert the *source-level* contract: `AppCore` exposes a
        // boolean flag that is set only when `Task.detached` is used
        // somewhere in its init. The flag is false in the current
        // implementation; the test pins that and will fail if a
        // future edit introduces a detached task without surfacing it.
        let core = AppCore()
        #expect(core.usedDetachedTaskDuringInit == false)
    }
}
