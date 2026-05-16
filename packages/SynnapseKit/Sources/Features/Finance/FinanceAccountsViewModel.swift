import Foundation
import Observation
import Models

public enum FinanceAccountsState: Sendable, Equatable {
    case idle
    case loading
    case results([FinanceAccount])
    case empty
    case error(String)
}

@MainActor
@Observable
public final class FinanceAccountsViewModel {
    public private(set) var state: FinanceAccountsState = .idle
    public private(set) var accounts: [FinanceAccount] = []
    public var searchText: String = ""
    public var selectedKind: AccountKind?
    public var selected: FinanceAccount?

    private let api: FinanceAPI
    private let repository: FinanceRepository

    public init(api: FinanceAPI) {
        self.api = api
        self.repository = FinanceRepository(api: api)
    }

    public func refresh() async {
        state = .loading
        do {
            try await repository.refreshAccounts()
            self.accounts = await repository.accounts
            state = accounts.isEmpty ? .empty : .results(filtered())
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func filtered() -> [FinanceAccount] {
        accounts.filter { account in
            if let kind = selectedKind, account.kind != kind { return false }
            if !searchText.isEmpty {
                let needle = searchText.lowercased()
                let hay = "\(account.name)\n\(account.officialName ?? "")\n\(account.institutionName ?? "")".lowercased()
                if !hay.contains(needle) { return false }
            }
            return true
        }
    }

    public func injectForSnapshots(accounts: [FinanceAccount]) {
        self.accounts = accounts
        self.state = accounts.isEmpty ? .empty : .results(accounts)
    }
}
