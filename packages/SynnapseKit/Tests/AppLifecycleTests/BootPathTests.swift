import Foundation
import Testing
@testable import AppLifecycle
@testable import Auth
@testable import Features
@testable import Networking
@testable import Models

/// The login gate was removed: Synnapse boots straight into the cockpit
/// shell. These tests pin two contracts:
///
///   1. `AppCore` can be constructed and brought up to bootstrap even
///      when the auth view model is in the default `.signedOut` state.
///      This is what proves the boot path no longer trips a sign-in
///      requirement.
///
///   2. When the core is wired in demo mode, `bootstrap()` seeds the
///      Mock APIs so the surfaces render representative data instead of
///      empty `.idle` snapshots. This is what makes the user see
///      Finance / Life / Advisors populated on first paint.
@Suite("Boot path — no auth gate")
@MainActor
struct BootPathTests {

    @Test("Boot succeeds with a signed-out AuthViewModel")
    func bootSucceedsWhenSignedOut() async {
        let core = AppCore(useDemoData: true)
        // The auth state must be `.signedOut` by default — the cockpit
        // shell is rendered regardless. This pins that the construction
        // path no longer awaits a session.
        #expect(core.auth.state == .signedOut)
        await core.bootstrap()
        // `restoreFromStore()` on a fresh keychain leaves state at
        // `.signedOut` (or `.error` on simulator hosts without keychain
        // entitlements). Either way the boot must not transition to
        // `.signedIn` implicitly.
        switch core.auth.state {
        case .signedIn:
            Issue.record("boot path implicitly signed the user in — login gate must be off")
        default:
            break
        }
    }

    @Test("Demo mode wires the Mock APIs")
    func demoModeWiresMockAPIs() {
        let core = AppCore(useDemoData: true)
        #expect(core.usesDemoData == true)
        #expect(core.demoFinanceAPI != nil)
        #expect(core.demoLifeAPI != nil)
        #expect(core.demoAdvisorsAPI != nil)
    }

    @Test("Release-mode wiring keeps the Live APIs")
    func releaseModeWiresLiveAPIs() {
        let core = AppCore(useDemoData: false)
        #expect(core.usesDemoData == false)
        #expect(core.demoFinanceAPI == nil)
        #expect(core.demoLifeAPI == nil)
        #expect(core.demoAdvisorsAPI == nil)
    }

    @Test("Demo bootstrap populates the Finance view model")
    func demoBootstrapPopulatesFinance() async {
        let core = AppCore(useDemoData: true)
        // VM starts idle.
        #expect(core.financePersonal.state == .idle)
        await core.bootstrap()
        // Trigger the same refresh the shell does after seeding so the
        // assertion doesn't rely on internal scheduling.
        await core.financePersonal.refresh()
        if case .ready(let snapshot) = core.financePersonal.state {
            #expect(!snapshot.accounts.isEmpty, "demo seed must produce accounts")
        } else {
            Issue.record("expected .ready after demo bootstrap, got \(core.financePersonal.state)")
        }
    }

    @Test("Demo bootstrap populates the Advisors list")
    func demoBootstrapPopulatesAdvisors() async {
        let core = AppCore(useDemoData: true)
        await core.bootstrap()
        await core.advisors.refresh()
        // The list must arrive populated; the cockpit's Advisors
        // surface is what the user sees on boot without a sign-in.
        let count = core.advisors.advisors.count
        #expect(count > 0, "demo seed must populate advisor personas (got \(count))")
    }
}
