import Foundation

/// Hand-curated demo memberships so the surface paints a believable
/// 7-row state on first launch — before any live transactions exist.
///
/// Two duplicate clusters are deliberately seeded so the optimiser
/// has interesting work to do on the demo data:
///
///   * **Music**: Spotify ($10.99) + Apple Music ($10.99) — the
///     optimiser will emit a `cancelDuplicate` tip for Apple Music
///     (which is also flagged `unused`, doubling the signal in the UI).
///   * **AI tools**: Anthropic ($20) + ChatGPT Plus ($20) — Anthropic
///     is `atRisk` due to a recent $18→$20 price hike, and ChatGPT is
///     `unused`. Cluster savings round out the "you could recover
///     $X/mo" headline.
public enum MembershipsDemoData {

    /// Stable demo set anchored to "now" so the chargeHistory dates
    /// always look fresh relative to launch. The sample memberships
    /// carry `isSample = true` so the UI can render the "Demo data"
    /// affordance if it wants to.
    public static func sampleMemberships(relativeTo now: Date = Date()) -> [Membership] {
        let cal = Calendar(identifier: .gregorian)

        func days(_ n: Int) -> Date {
            cal.date(byAdding: .day, value: -n, to: now) ?? now
        }
        func forward(_ n: Int) -> Date {
            cal.date(byAdding: .day, value: n, to: now) ?? now
        }

        func attach(
            id: String,
            merchant: String,
            monthly: Decimal,
            cadence: Int,
            lastChargedDaysAgo: Int,
            occurrences: Int,
            status: MembershipStatus,
            logoDomain: String?,
            history: [(daysAgo: Int, amount: Decimal)],
            confidence: Double = 0.92
        ) -> Membership {
            let lastCharged = days(lastChargedDaysAgo)
            let nextExpected = forward(cadence - lastChargedDaysAgo)
            let chargeHistory = history
                .map { ChargeHistoryPoint(id: "\(id).hist.\($0.daysAgo)",
                                          date: days($0.daysAgo),
                                          amount: $0.amount) }
                .sorted { $0.date < $1.date }
            let firstSeen = chargeHistory.first?.date ?? lastCharged

            let guide = logoDomain.flatMap { CancellationGuideCatalog.guide(for: $0) }
            return Membership(
                id: id,
                merchant: merchant,
                monthlyCost: monthly,
                annualCost: monthly * 12,
                currency: "USD",
                cadenceDays: cadence,
                firstSeenAt: firstSeen,
                lastChargedAt: lastCharged,
                nextExpectedAt: nextExpected,
                occurrenceCount: occurrences,
                status: status,
                logoDomain: logoDomain,
                sourceTransactionIds: chargeHistory.map(\.id),
                cancellationGuide: guide,
                optimizationTips: [],
                chargeHistory: chargeHistory,
                confidence: confidence,
                isSample: true
            )
        }

        return [
            attach(
                id: "demo.netflix",
                merchant: "Netflix",
                monthly: Decimal(string: "15.49") ?? 15,
                cadence: 30,
                lastChargedDaysAgo: 4,
                occurrences: 6,
                status: .active,
                logoDomain: "netflix.com",
                history: [
                    (154, Decimal(string: "15.49") ?? 15),
                    (124, Decimal(string: "15.49") ?? 15),
                    (94,  Decimal(string: "15.49") ?? 15),
                    (64,  Decimal(string: "15.49") ?? 15),
                    (34,  Decimal(string: "15.49") ?? 15),
                    (4,   Decimal(string: "15.49") ?? 15)
                ]
            ),
            attach(
                id: "demo.spotify",
                merchant: "Spotify",
                monthly: Decimal(string: "10.99") ?? 11,
                cadence: 30,
                lastChargedDaysAgo: 8,
                occurrences: 6,
                status: .active,
                logoDomain: "spotify.com",
                history: [
                    (158, Decimal(string: "10.99") ?? 11),
                    (128, Decimal(string: "10.99") ?? 11),
                    (98,  Decimal(string: "10.99") ?? 11),
                    (68,  Decimal(string: "10.99") ?? 11),
                    (38,  Decimal(string: "10.99") ?? 11),
                    (8,   Decimal(string: "10.99") ?? 11)
                ]
            ),
            attach(
                id: "demo.appleMusic",
                merchant: "Apple Music",
                monthly: Decimal(string: "10.99") ?? 11,
                cadence: 30,
                lastChargedDaysAgo: 25,
                occurrences: 5,
                status: .unused,
                logoDomain: "apple.com",
                history: [
                    (145, Decimal(string: "10.99") ?? 11),
                    (115, Decimal(string: "10.99") ?? 11),
                    (85,  Decimal(string: "10.99") ?? 11),
                    (55,  Decimal(string: "10.99") ?? 11),
                    (25,  Decimal(string: "10.99") ?? 11)
                ],
                confidence: 0.91
            ),
            attach(
                id: "demo.anthropic",
                merchant: "Anthropic Claude",
                monthly: 20,
                cadence: 30,
                lastChargedDaysAgo: 3,
                occurrences: 4,
                status: .atRisk,
                logoDomain: "anthropic.com",
                history: [
                    (93, 18),
                    (63, 18),
                    (33, 20),
                    (3,  20)
                ]
            ),
            attach(
                id: "demo.nytimes",
                merchant: "NYTimes",
                monthly: Decimal(string: "4.25") ?? 4,
                cadence: 30,
                lastChargedDaysAgo: 12,
                occurrences: 5,
                status: .active,
                logoDomain: "nytimes.com",
                history: [
                    (132, Decimal(string: "4.25") ?? 4),
                    (102, Decimal(string: "4.25") ?? 4),
                    (72,  Decimal(string: "4.25") ?? 4),
                    (42,  Decimal(string: "4.25") ?? 4),
                    (12,  Decimal(string: "4.25") ?? 4)
                ]
            ),
            attach(
                id: "demo.equinox",
                merchant: "Equinox",
                monthly: 245,
                cadence: 30,
                lastChargedDaysAgo: 1,
                occurrences: 4,
                status: .active,
                logoDomain: "equinox.com",
                history: [
                    (91, 245),
                    (61, 245),
                    (31, 245),
                    (1,  245)
                ]
            ),
            attach(
                id: "demo.chatgpt",
                merchant: "ChatGPT Plus",
                monthly: 20,
                cadence: 30,
                lastChargedDaysAgo: 27,
                occurrences: 4,
                status: .unused,
                logoDomain: "openai.com",
                history: [
                    (117, 20),
                    (87,  20),
                    (57,  20),
                    (27,  20)
                ]
            )
        ]
    }
}
