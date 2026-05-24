import Foundation
import Models

/// One projected balance point in the cash-flow forecast. The
/// `balance` is the central estimate; `lowerBound` / `upperBound` form
/// a 1-σ confidence band the UI draws as a shaded area underneath the
/// dashed projection line. All three are signed (positive = asset).
public struct ForecastPoint: Sendable, Hashable, Codable {
    public let date: Date
    public let balance: Decimal
    public let lowerBound: Decimal
    public let upperBound: Decimal

    public init(date: Date, balance: Decimal, lowerBound: Decimal, upperBound: Decimal) {
        self.date = date
        self.balance = balance
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }
}

/// A projected charge from a detected recurring service. Drives the
/// "Predicted Sirius XM charge May 24: $37" row.
public struct PredictedCharge: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let merchantName: String
    public let amount: Decimal
    public let date: Date

    public init(id: String, merchantName: String, amount: Decimal, date: Date) {
        self.id = id
        self.merchantName = merchantName
        self.amount = amount
        self.date = date
    }
}

/// Full forecast envelope for one account. `series` is the day-by-day
/// projection across the requested horizon; `zeroCrossing` is non-nil
/// when the central estimate dips below zero in the window;
/// `nextThirtyDaysTotal` is the sum of predicted recurring charges in
/// the next 30 days (used for the "Your next 30 days of bills total"
/// callout).
public struct Forecast: Sendable, Hashable, Codable {
    public let accountId: String
    public let series: [ForecastPoint]
    public let zeroCrossing: Date?
    public let predictedCharges: [PredictedCharge]
    public let nextThirtyDaysTotal: Decimal

    public init(
        accountId: String,
        series: [ForecastPoint],
        zeroCrossing: Date?,
        predictedCharges: [PredictedCharge],
        nextThirtyDaysTotal: Decimal
    ) {
        self.accountId = accountId
        self.series = series
        self.zeroCrossing = zeroCrossing
        self.predictedCharges = predictedCharges
        self.nextThirtyDaysTotal = nextThirtyDaysTotal
    }
}
