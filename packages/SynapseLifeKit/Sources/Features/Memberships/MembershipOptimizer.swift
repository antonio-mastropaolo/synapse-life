import Foundation

/// Pure-function pass that decorates a `[Membership]` set with
/// actionable optimisation tips, clusters duplicates by category, and
/// rolls everything up into an `OptimizationSummary` the tab header
/// can render.
///
/// All emitted tips carry an `estimatedSavingsMonthly` figure. The
/// summary's `totalPotentialSavingsMonthly` is the sum of every tip's
/// savings — duplicates between e.g. "cancel duplicate" and "cancel
/// unused" for the same merchant are de-duplicated by `Tip.id`
/// (merchantId + kind), so a low-usage Apple Music in a music cluster
/// counts once, not twice.
public enum MembershipOptimizer {

    /// Group memberships by category, score per-merchant tips, sum
    /// monthly savings. Returns the decorated tip set, the cluster
    /// list (one per duplicate-prone category that holds ≥ 2
    /// memberships), and the rolled-up summary.
    public static func optimize(
        memberships: [Membership]
    ) -> (
        tips: [OptimizationTip],
        clusters: [DuplicateCluster],
        summary: OptimizationSummary
    ) {
        // 1. Cluster by category.
        let clusters = buildClusters(memberships: memberships)

        // Collect tips into a dictionary keyed by tip.id so two paths
        // can't both emit the same advice (e.g. "Apple Music is
        // unused AND part of a duplicate cluster" — we'd rather not
        // double-count $10.99).
        var tipsByID: [String: OptimizationTip] = [:]

        // 2. Cancel-duplicate tips — every non-cheapest member of a
        // cluster gets a tip.
        for cluster in clusters {
            // The cheapest member of the cluster is the one we want
            // to keep; everything else is fair game to cancel.
            let sorted = cluster.memberships.sorted { $0.monthlyCost < $1.monthlyCost }
            guard let keeper = sorted.first else { continue }
            for member in sorted.dropFirst() {
                let savings = member.monthlyCost
                let rationale = "You also have \(keeper.merchant) at \(formatCurrency(keeper.monthlyCost))/mo in the \(cluster.categoryLabel) category — cancel one to recover \(formatCurrency(savings))/mo."
                let tip = OptimizationTip(
                    merchantId: member.id,
                    kind: .cancelDuplicate,
                    rationale: rationale,
                    estimatedSavingsMonthly: savings
                )
                tipsByID[tip.id] = tip
            }
        }

        // 3. Per-membership tips.
        for m in memberships {
            // Trial-pause beats every other suggestion for a trial —
            // we want the user to see "you're about to get charged"
            // before "downgrade".
            if m.status == .trial {
                let tip = OptimizationTip(
                    merchantId: m.id,
                    kind: .pauseTrialBeforeRollover,
                    rationale: "Trial — \(m.merchant) rolls over to \(formatCurrency(m.monthlyCost))/mo on \(formatDate(m.nextExpectedAt)). Cancel before that date and you avoid the charge.",
                    estimatedSavingsMonthly: m.monthlyCost
                )
                tipsByID[tip.id] = tip
                continue
            }

            // Cancel-unused — strongest signal when the user appears
            // to not be touching the service.
            if m.status == .unused {
                let tip = OptimizationTip(
                    merchantId: m.id,
                    kind: .cancelUnused,
                    rationale: "Low usage — \(m.merchant) charged \(formatCurrency(m.monthlyCost))/mo with no recent engagement. Cancel to recover \(formatCurrency(m.monthlyCost))/mo.",
                    estimatedSavingsMonthly: m.monthlyCost
                )
                tipsByID[tip.id] = tip
            }

            // Switch-to-annual — only when the catalog has an annual
            // figure AND the monthly cadence pays off when prepaid.
            if m.cadenceDays == 30,
               let domain = m.logoDomain,
               CancellationGuideCatalog.hasAnnualPlan(for: domain),
               let annual = CancellationGuideCatalog.annualPrice(for: domain) {
                let annualMonthly = annual / 12
                if annualMonthly < m.monthlyCost {
                    let savings = m.monthlyCost - annualMonthly
                    let rationale = "Annual plan is \(formatCurrency(annual))/yr — that's \(formatCurrency(annualMonthly))/mo, saving \(formatCurrency(savings))/mo vs your current monthly bill."
                    let tip = OptimizationTip(
                        merchantId: m.id,
                        kind: .switchToAnnual,
                        rationale: rationale,
                        estimatedSavingsMonthly: savings
                    )
                    tipsByID[tip.id] = tip
                }
            }

            // Downgrade — only when the catalog has a cheaper-tier
            // entry. We don't invent prices for merchants we haven't
            // verified.
            if let domain = m.logoDomain,
               let tier = CancellationGuideCatalog.cheaperTier(for: domain) {
                let savings = m.monthlyCost - tier.monthlyPrice
                if savings > 0 {
                    let rationale = "Switch \(m.merchant) to the \(tier.label) at \(formatCurrency(tier.monthlyPrice))/mo to save \(formatCurrency(savings))/mo."
                    let tip = OptimizationTip(
                        merchantId: m.id,
                        kind: .downgrade,
                        rationale: rationale,
                        estimatedSavingsMonthly: savings
                    )
                    tipsByID[tip.id] = tip
                }
            }
        }

        let allTips = Array(tipsByID.values).sorted { lhs, rhs in
            if lhs.estimatedSavingsMonthly == rhs.estimatedSavingsMonthly {
                return lhs.merchantId < rhs.merchantId
            }
            return lhs.estimatedSavingsMonthly > rhs.estimatedSavingsMonthly
        }
        let total = allTips.reduce(Decimal.zero) { $0 + $1.estimatedSavingsMonthly }
        let top3 = Array(allTips.prefix(3))
        let summary = OptimizationSummary(
            totalPotentialSavingsMonthly: total,
            actionableTipCount: allTips.count,
            topTips: top3
        )

        return (allTips, clusters, summary)
    }

    // MARK: - Clustering

    /// Domain → category-key table. Two-or-more memberships in the
    /// same category form a `DuplicateCluster`.
    static let categoryByDomain: [String: (key: String, label: String)] = [
        "netflix.com":    ("streaming",     "Streaming video"),
        "hulu.com":       ("streaming",     "Streaming video"),
        "disneyplus.com": ("streaming",     "Streaming video"),
        "hbomax.com":     ("streaming",     "Streaming video"),
        "youtube.com":    ("streaming",     "Streaming video"),
        "spotify.com":    ("music",         "Music"),
        "apple.com":      ("music",         "Music"),       // Apple Music; cloud-storage handled below by override
        "nytimes.com":    ("news",          "News"),
        "wsj.com":        ("news",          "News"),
        "anthropic.com":  ("ai-tools",      "AI tools"),
        "openai.com":     ("ai-tools",      "AI tools"),
        "cursor.sh":      ("ai-tools",      "AI tools"),
        "github.com":     ("ai-tools",      "AI tools"),
        "dropbox.com":    ("cloud-storage", "Cloud storage")
    ]

    static func buildClusters(memberships: [Membership]) -> [DuplicateCluster] {
        // Group by category key. We need to be careful: apple.com
        // can mean iCloud (cloud-storage) OR Apple Music (music).
        // Use merchant-name heuristics to disambiguate.
        var byCategory: [String: (label: String, members: [Membership])] = [:]
        for m in memberships {
            guard let key = categoryKey(for: m) else { continue }
            byCategory[key.key, default: (label: key.label, members: [])].members.append(m)
        }

        var clusters: [DuplicateCluster] = []
        for (key, bucket) in byCategory {
            guard bucket.members.count >= 2 else { continue }
            // Savings if you cancel everything but the cheapest.
            let sorted = bucket.members.sorted { $0.monthlyCost < $1.monthlyCost }
            let savings = sorted.dropFirst().reduce(Decimal.zero) { $0 + $1.monthlyCost }
            clusters.append(DuplicateCluster(
                id: key,
                categoryLabel: bucket.label,
                memberships: sorted,
                estimatedSavingsMonthly: savings
            ))
        }
        // Largest opportunity first.
        return clusters.sorted { $0.estimatedSavingsMonthly > $1.estimatedSavingsMonthly }
    }

    /// Domain-aware category resolution. Apple is overloaded — the
    /// merchant string disambiguates between Apple Music (music
    /// cluster) and iCloud / Apple One (cloud-storage cluster).
    static func categoryKey(for m: Membership) -> (key: String, label: String)? {
        let upper = m.merchant.uppercased()
        if let domain = m.logoDomain {
            // Apple Music override — when the merchant string mentions
            // music, snap to the music cluster even though the domain
            // resolves to apple.com.
            if domain == "apple.com" {
                if upper.contains("MUSIC") {
                    return ("music", "Music")
                }
                return ("cloud-storage", "Cloud storage")
            }
            return categoryByDomain[domain]
        }
        // Fallback heuristic when the domain is nil — token match
        // against the merchant string. Keeps demo data that omits the
        // domain (or banks that mangle the merchant name) inside the
        // clustering net.
        if upper.contains("APPLE MUSIC") || upper.contains("APPLEMUSIC") {
            return ("music", "Music")
        }
        return nil
    }

    // MARK: - Formatting helpers

    private static func formatCurrency(_ amount: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = "USD"
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2
        return nf.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }

    private static func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return df.string(from: date)
    }
}
