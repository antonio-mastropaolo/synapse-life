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

    /// Surfaced for [[CrashFreeLaunchTests]] — set to `true` only if a
    /// future edit introduces a `Task.detached` somewhere in `init`.
    /// Today: no detached work is needed before the scene mounts; all
    /// async bootstrap is folded into `bootstrap()` which the shell
    /// awaits from `.task`.
    public let usedDetachedTaskDuringInit: Bool = false

    public init(baseURLOverride: String? = nil) {
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

        let financeAPI = LiveFinanceAPI(client: client)
        self.financePersonal = FinancePersonalViewModel(api: financeAPI)
        self.financeAccounts = FinanceAccountsViewModel(api: financeAPI)
        self.financeTransactions = FinanceTransactionsViewModel(api: financeAPI, accountId: nil)
        self.financeInvestments = FinanceInvestmentsViewModel(api: financeAPI)

        self.lifeAPI = LiveLifeAPI(client: client, serverContractLive: false)

        self.advisors = AdvisorsListViewModel(api: LiveAdvisorsAPI(client: client))

        self.settings = SettingsViewModel(store: UserDefaultsSettingsStore())
    }

    /// Async bootstrap mirror of what the shell's `bootstrapIfNeeded`
    /// would call. Currently restores the auth session from keychain.
    public func bootstrap() async {
        await auth.restoreFromStore()
    }
}
