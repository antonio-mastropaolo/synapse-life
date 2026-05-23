import Foundation
import Models

/// DTO ↔ persisted projections. All of these are pure functions on Sendable
/// inputs / outputs; the `@Model` reference types only live inside the
/// `ModelActor`s in `Stores/`.

extension PersistedFinanceAccount {

    /// Build a `PersistedFinanceAccount` from the Sendable DTO. Used by the
    /// store actors when ingesting a sync delta or seeding from `DemoData`.
    public static func from(
        _ dto: FinanceAccount,
        syncedAt: Date = Date()
    ) -> PersistedFinanceAccount {
        PersistedFinanceAccount(
            id: dto.id,
            institutionId: dto.institutionId,
            institutionName: dto.institutionName,
            name: dto.name,
            officialName: dto.officialName,
            mask: dto.mask,
            kindRaw: dto.kind.rawValue,
            currency: dto.currency,
            currentBalance: dto.currentBalance,
            availableBalance: dto.availableBalance,
            limitAmount: dto.limitAmount,
            balanceCapturedAt: dto.balanceCapturedAt,
            lastSyncedAt: syncedAt
        )
    }

    /// Snapshot back into the Sendable DTO so the value can cross actors.
    public func toDTO() -> FinanceAccount {
        FinanceAccount(
            id: id,
            institutionId: institutionId,
            institutionName: institutionName,
            name: name,
            officialName: officialName,
            mask: mask,
            kind: kind,
            currency: currency,
            currentBalance: currentBalance,
            availableBalance: availableBalance,
            limitAmount: limitAmount,
            balanceCapturedAt: balanceCapturedAt
        )
    }

    /// In-place upsert from a DTO, preserving identity. Returns `true` if
    /// any field changed (used by the store actor to decide whether the
    /// NotificationCenter event should fire).
    @discardableResult
    public func update(from dto: FinanceAccount, syncedAt: Date = Date()) -> Bool {
        var changed = false
        if institutionId != dto.institutionId    { institutionId = dto.institutionId; changed = true }
        if institutionName != dto.institutionName { institutionName = dto.institutionName; changed = true }
        if name != dto.name                       { name = dto.name; changed = true }
        if officialName != dto.officialName       { officialName = dto.officialName; changed = true }
        if mask != dto.mask                       { mask = dto.mask; changed = true }
        if kindRaw != dto.kind.rawValue           { kindRaw = dto.kind.rawValue; changed = true }
        if currency != dto.currency               { currency = dto.currency; changed = true }
        if currentBalance != dto.currentBalance   { currentBalance = dto.currentBalance; changed = true }
        if availableBalance != dto.availableBalance { availableBalance = dto.availableBalance; changed = true }
        if limitAmount != dto.limitAmount         { limitAmount = dto.limitAmount; changed = true }
        if balanceCapturedAt != dto.balanceCapturedAt { balanceCapturedAt = dto.balanceCapturedAt; changed = true }
        lastSyncedAt = syncedAt
        return changed
    }
}

extension PersistedTransaction {

    public static func from(
        _ dto: Transaction,
        syncedAt: Date = Date()
    ) -> PersistedTransaction {
        let categoryRaw: String?
        switch dto.category {
        case .knownCategory(let s): categoryRaw = s
        case .unknown:              categoryRaw = nil
        }
        return PersistedTransaction(
            id: dto.id,
            accountId: dto.accountId,
            accountName: dto.accountName,
            amount: dto.amount,
            currency: dto.currency,
            date: dto.date,
            name: dto.name,
            merchantName: dto.merchantName,
            categoryRaw: categoryRaw,
            subcategory: dto.subcategory,
            pending: dto.pending,
            lastSyncedAt: syncedAt
        )
    }

    public func toDTO() -> Transaction {
        Transaction(
            id: id,
            accountId: accountId,
            accountName: accountName,
            amount: amount,
            currency: currency,
            date: date,
            name: name,
            merchantName: merchantName,
            category: category,
            subcategory: subcategory,
            pending: pending
        )
    }

    @discardableResult
    public func update(from dto: Transaction, syncedAt: Date = Date()) -> Bool {
        var changed = false
        let newCategoryRaw: String? = {
            switch dto.category {
            case .knownCategory(let s): return s
            case .unknown: return nil
            }
        }()
        if accountId != dto.accountId             { accountId = dto.accountId; changed = true }
        if accountName != dto.accountName         { accountName = dto.accountName; changed = true }
        if amount != dto.amount                   { amount = dto.amount; changed = true }
        if currency != dto.currency               { currency = dto.currency; changed = true }
        if date != dto.date                       { date = dto.date; changed = true }
        if name != dto.name                       { name = dto.name; changed = true }
        if merchantName != dto.merchantName       { merchantName = dto.merchantName; changed = true }
        if categoryRaw != newCategoryRaw          { categoryRaw = newCategoryRaw; changed = true }
        if subcategory != dto.subcategory         { subcategory = dto.subcategory; changed = true }
        if pending != dto.pending                 { pending = dto.pending; changed = true }
        lastSyncedAt = syncedAt
        return changed
    }
}

extension PersistedInvestmentPosition {

    public static func from(
        _ dto: InvestmentPosition,
        syncedAt: Date = Date()
    ) -> PersistedInvestmentPosition {
        PersistedInvestmentPosition(
            securityId: dto.securityId,
            accountId: dto.accountId,
            accountName: dto.accountName,
            ticker: dto.ticker,
            positionName: dto.name,
            kindRaw: dto.kind.rawValue,
            quantity: dto.quantity,
            price: dto.price,
            value: dto.value,
            costBasis: dto.costBasis,
            unrealizedPnL: dto.unrealizedPnL,
            unrealizedPnLPct: dto.unrealizedPnLPct,
            currency: dto.currency,
            lastSyncedAt: syncedAt
        )
    }

    public func toDTO() -> InvestmentPosition {
        InvestmentPosition(
            securityId: securityId,
            accountId: accountId,
            accountName: accountName,
            ticker: ticker,
            name: positionName,
            kind: kind,
            quantity: quantity,
            price: price,
            value: value,
            costBasis: costBasis,
            unrealizedPnL: unrealizedPnL,
            unrealizedPnLPct: unrealizedPnLPct,
            currency: currency
        )
    }

    @discardableResult
    public func update(from dto: InvestmentPosition, syncedAt: Date = Date()) -> Bool {
        var changed = false
        if accountName != dto.accountName     { accountName = dto.accountName; changed = true }
        if ticker != dto.ticker               { ticker = dto.ticker; changed = true }
        if positionName != dto.name           { positionName = dto.name; changed = true }
        if kindRaw != dto.kind.rawValue       { kindRaw = dto.kind.rawValue; changed = true }
        if quantity != dto.quantity           { quantity = dto.quantity; changed = true }
        if price != dto.price                 { price = dto.price; changed = true }
        if value != dto.value                 { value = dto.value; changed = true }
        if costBasis != dto.costBasis         { costBasis = dto.costBasis; changed = true }
        if unrealizedPnL != dto.unrealizedPnL { unrealizedPnL = dto.unrealizedPnL; changed = true }
        if unrealizedPnLPct != dto.unrealizedPnLPct { unrealizedPnLPct = dto.unrealizedPnLPct; changed = true }
        if currency != dto.currency           { currency = dto.currency; changed = true }
        lastSyncedAt = syncedAt
        return changed
    }
}

extension PersistedNotification {

    public static func from(
        _ dto: ProactiveSignal,
        createdAt: Date = Date()
    ) -> PersistedNotification {
        PersistedNotification(
            id: dto.id,
            kindRaw: dto.kind.rawValue,
            headline: dto.headline,
            body: dto.body,
            subjectId: dto.subjectId,
            date: dto.date,
            severityRaw: dto.severity.rawValue,
            severityRank: dto.severity.rank,
            dismissed: false,
            createdAt: createdAt
        )
    }

    /// `kind` / `severity` fall back to a concrete case on an unrecognised
    /// raw string. That only happens against data written by a *newer* schema
    /// than this binary; rows this binary wrote always round-trip exactly.
    public func toDTO() -> ProactiveSignal {
        ProactiveSignal(
            id: id,
            kind: kind ?? .anomalousSpend,
            headline: headline,
            body: body,
            subjectId: subjectId,
            date: date,
            severity: severity ?? .info
        )
    }

    /// In-place content update from a re-run. Returns `true` if any surfaced
    /// field changed. Deliberately does NOT touch `dismissed` or `createdAt`:
    /// a nightly re-evaluation refreshes the wording, never the user's
    /// dismissal or the original retention clock.
    @discardableResult
    public func update(from dto: ProactiveSignal) -> Bool {
        var changed = false
        if kindRaw != dto.kind.rawValue       { kindRaw = dto.kind.rawValue; changed = true }
        if headline != dto.headline           { headline = dto.headline; changed = true }
        if body != dto.body                   { body = dto.body; changed = true }
        if subjectId != dto.subjectId         { subjectId = dto.subjectId; changed = true }
        if date != dto.date                   { date = dto.date; changed = true }
        if severityRaw != dto.severity.rawValue {
            severityRaw = dto.severity.rawValue
            severityRank = dto.severity.rank
            changed = true
        }
        return changed
    }
}
