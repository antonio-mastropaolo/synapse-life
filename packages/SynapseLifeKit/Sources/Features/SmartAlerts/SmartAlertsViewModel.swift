import Foundation
import Observation
import Models

/// Drives the SmartAlertsScene. Holds the user's installed rules + the
/// AI-suggested rules + the recent fired alerts. Rule installation /
/// deletion is local-only today — future work persists to the server.
@MainActor
@Observable
public final class SmartAlertsViewModel {
    public private(set) var rules: [AlertRule] = []
    public private(set) var suggestions: [AlertRule] = []
    public private(set) var firedAlerts: [FiredAlert] = []

    private let clock: @MainActor () -> Date

    public init(
        initialRules: [AlertRule] = [],
        clock: @MainActor @escaping () -> Date = { Date() }
    ) {
        self.rules = initialRules
        self.clock = clock
    }

    public func refresh(accounts: [FinanceAccount], transactions: [Transaction], priorMerchants: Set<String> = []) {
        let snapshot = AlertsSnapshot(
            accounts: accounts,
            transactions: transactions,
            priorMerchants: priorMerchants,
            now: clock()
        )
        firedAlerts = SmartAlertsEngine.evaluate(rules: rules, snapshot: snapshot)
        suggestions = SmartAlertsEngine.suggestRules(snapshot: snapshot, existing: rules)
    }

    public func add(_ rule: AlertRule) {
        var copy = rule
        if !rule.enabled {
            copy = AlertRule(
                id: rule.id,
                kind: rule.kind,
                enabled: true,
                createdAt: rule.createdAt,
                isAISuggested: false
            )
        }
        rules.append(copy)
        suggestions.removeAll { $0.id == rule.id }
    }

    public func remove(_ ruleId: String) {
        rules.removeAll { $0.id == ruleId }
    }

    public func setEnabled(_ ruleId: String, enabled: Bool) {
        guard let idx = rules.firstIndex(where: { $0.id == ruleId }) else { return }
        let prior = rules[idx]
        rules[idx] = AlertRule(
            id: prior.id,
            kind: prior.kind,
            enabled: enabled,
            createdAt: prior.createdAt,
            isAISuggested: prior.isAISuggested
        )
    }

    public func injectForSnapshots(rules: [AlertRule], suggestions: [AlertRule], fired: [FiredAlert]) {
        self.rules = rules
        self.suggestions = suggestions
        self.firedAlerts = fired
    }
}
