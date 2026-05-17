import Foundation
import Observation
import Models
import Networking
import Auth
import Features

/// Cross-platform construction seam shared by the macOS and iOS app
/// shells. Both `SynnapseMacApp.AppModel` and `SynnapseiOSApp.AppModel`
/// build the same set of view models from the same `Networking`,
/// `Auth`, and `Features` types — `AppCore` lifts that wiring into the
/// package so the shells can be thin (just scenes + platform glue) and
/// so the wiring itself is testable from `swift test`.
///
/// Scope: Synnapse is a private-life client. Work-flavoured surfaces
/// from the synapse-v2 web app (Spotlight, Approvals, People, Inbox,
/// Sequences, Octagon, Trading Desk) deliberately do not exist here.
/// The shells host Finance, Life, Advisors, and Settings only.
@MainActor
@Observable
public final class AppCore {

    public let baseURL: URL
    public let auth: AuthViewModel
    public let financePersonal: FinancePersonalViewModel
    public let financeAccounts: FinanceAccountsViewModel
    public let financeTransactions: FinanceTransactionsViewModel
    public let financeInvestments: FinanceInvestmentsViewModel
    public let lifeAPI: LifeAPI
    public let advisors: AdvisorsListViewModel
    public let settings: SettingsViewModel

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
        let envBase = ProcessInfo.processInfo.environment["SYNNAPSE_API_BASE"]
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

        self.financePersonal = FinancePersonalViewModel(api: financeAPI)
        self.financeAccounts = FinanceAccountsViewModel(api: financeAPI)
        self.financeTransactions = FinanceTransactionsViewModel(api: financeAPI, accountId: nil)
        self.financeInvestments = FinanceInvestmentsViewModel(api: financeAPI)

        self.lifeAPI = lifeAPIWire

        self.advisors = AdvisorsListViewModel(api: advisorsAPIWire)

        self.settings = SettingsViewModel(store: UserDefaultsSettingsStore())
    }

    /// Async bootstrap mirror of what the shell's `bootstrapIfNeeded`
    /// would call. Restores the auth session from keychain and, when
    /// the core was wired with Mock APIs, seeds the demo fixtures so
    /// the cockpit renders something on first paint.
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
    }
}
