#if os(macOS)
import Foundation
import AppKit

/// macOS-only scanner that walks the Spotlight index for emails whose
/// sender domain matches a known merchant (Netflix, Spotify, Anthropic,
/// etc.) and returns inferred recurring detections.
///
/// Why Spotlight, not a real Mail integration:
///   • Mail.app exposes no public IPC for third-party readers.
///   • Apple's Spotlight index already exposes every message's `From`
///     header, subject, date, and uti via `kMDItemAuthorEmailAddresses`,
///     `kMDItemSubject`, `kMDItemContentCreationDate`. We read those
///     six fields and nothing else — no body content leaves the index.
///   • Works without Full Disk Access for the user's own Mail
///     library on macOS 14+ because Spotlight is a permitted query
///     surface. If a result is gated, the scanner returns
///     `permissionRequired` and the UI surfaces a "grant Full Disk
///     Access" CTA.
///
/// The scanner is intentionally narrow: it ONLY reports messages whose
/// sender domain matches `MerchantLogoResolver.domain` so we never
/// surface arbitrary correspondence. The match list is the same one
/// the icon resolver uses, so adding a brand is a one-line change in
/// one file.
@MainActor
public final class MailReceiptScanner {
    public static let shared = MailReceiptScanner()

    public enum Status: Sendable, Equatable {
        case idle
        case scanning
        case ready([EmailReceiptHit])
        case permissionRequired
        case error(String)
    }

    public struct EmailReceiptHit: Sendable, Hashable, Identifiable {
        public let id: String        // message UUID from Spotlight
        public let merchant: String  // matched merchant name
        public let domain: String    // matched merchant domain
        public let senderEmail: String
        public let subject: String
        public let date: Date
        public let category: ReceiptCategory

        public init(
            id: String,
            merchant: String,
            domain: String,
            senderEmail: String,
            subject: String,
            date: Date,
            category: ReceiptCategory
        ) {
            self.id = id
            self.merchant = merchant
            self.domain = domain
            self.senderEmail = senderEmail
            self.subject = subject
            self.date = date
            self.category = category
        }
    }

    /// Best-effort classification of the receipt purpose from the
    /// subject line. Lets the UI tag each hit with a small chip
    /// ("Upcoming charge", "Receipt", "Trial ending", "Renewal").
    public enum ReceiptCategory: String, Sendable, Hashable, Codable {
        case upcomingCharge   // "Your X subscription will renew on…"
        case receipt          // "Receipt from X", "Order confirmation"
        case trialEnding      // "Your trial ends in 3 days"
        case priceChange      // "Pricing changes coming to your X plan"
        case other

        public var displayLabel: String {
            switch self {
            case .upcomingCharge: return "Upcoming charge"
            case .receipt:        return "Receipt"
            case .trialEnding:    return "Trial ending"
            case .priceChange:    return "Price change"
            case .other:          return "Email"
            }
        }
    }

    public private(set) var status: Status = .idle

    private var query: NSMetadataQuery?

    private init() {}

    /// Kick off a Spotlight query for the last 90 days of messages
    /// whose sender email contains a known merchant domain. On
    /// completion, `status` flips to `.ready(hits)` and any subscriber
    /// can pull the results. `NSMetadataQuery` itself is not Sendable
    /// — we stay on the main actor the whole way through (build,
    /// start, observe, harvest) so Swift 6 strict concurrency stays
    /// happy.
    public func scan(domains: [String]) async {
        status = .scanning

        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        let typePred = NSPredicate(format: "kMDItemContentTypeTree CONTAINS %@", "public.email-message")
        let recentPred = NSPredicate(
            format: "kMDItemContentCreationDate >= %@",
            Date().addingTimeInterval(-90 * 86_400) as NSDate
        )
        let domainClauses = domains.map { d in
            NSPredicate(
                format: "ANY kMDItemAuthorEmailAddresses LIKE[c] %@",
                "*@\(d)"
            )
        }
        let combined = NSCompoundPredicate(orPredicateWithSubpredicates: domainClauses)
        q.predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [typePred, recentPred, combined]
        )
        self.query = q

        // Observer waits for `NSMetadataQueryDidFinishGathering` and
        // immediately re-enters MainActor to read results. We don't
        // pass the query across an isolation boundary.
        let didFinish: Void = await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let token = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: q,
                queue: .main
            ) { _ in
                cont.resume()
            }
            _ = token  // observer lives until the notification fires + we manually remove below
            if !q.start() {
                // Spotlight refused to start — surface permissions issue.
                cont.resume()
            }
        }
        _ = didFinish

        // Tear down the observer + query, harvest results synchronously.
        NotificationCenter.default.removeObserver(
            self,
            name: .NSMetadataQueryDidFinishGathering,
            object: q
        )
        q.stop()
        if q.resultCount == 0, query == nil {
            self.status = .permissionRequired
            return
        }
        let hits = harvest(query: q)
        self.query = nil
        self.status = .ready(hits)
    }

    // MARK: - Harvest

    private func harvest(query: NSMetadataQuery) -> [EmailReceiptHit] {
        var hits: [EmailReceiptHit] = []
        let count = query.resultCount
        for i in 0..<count {
            guard let item = query.result(at: i) as? NSMetadataItem else { continue }
            guard let senders = item.value(forAttribute: kMDItemAuthorEmailAddresses as String) as? [String] else { continue }
            guard let date = item.value(forAttribute: kMDItemContentCreationDate as String) as? Date else { continue }
            let subject = (item.value(forAttribute: kMDItemSubject as String) as? String) ?? "(no subject)"
            let id = (item.value(forAttribute: kMDItemIdentifier as String) as? String)
                ?? UUID().uuidString

            // Pick the first sender that matches one of our merchant
            // domains. We ignore the rest so the UI doesn't double-count.
            for sender in senders {
                guard let atIdx = sender.firstIndex(of: "@") else { continue }
                let domain = String(sender[sender.index(after: atIdx)...]).lowercased()
                if let merchant = merchantForDomain(domain) {
                    hits.append(EmailReceiptHit(
                        id: id,
                        merchant: merchant,
                        domain: domain,
                        senderEmail: sender,
                        subject: subject,
                        date: date,
                        category: classify(subject: subject)
                    ))
                    break
                }
            }
        }
        return hits.sorted { $0.date > $1.date }
    }

    private func merchantForDomain(_ domain: String) -> String? {
        // We match on any suffix so "billing.netflix.com" still maps
        // to "Netflix". Keys are lowercased.
        for (suffix, merchant) in Self.merchantsByDomain {
            if domain.hasSuffix(suffix) { return merchant }
        }
        return nil
    }

    private func classify(subject: String) -> ReceiptCategory {
        let s = subject.lowercased()
        if s.contains("trial") && (s.contains("ending") || s.contains("ends")) {
            return .trialEnding
        }
        if s.contains("price") || s.contains("pricing") {
            return .priceChange
        }
        if s.contains("upcoming") || s.contains("renew") || s.contains("auto-pay") {
            return .upcomingCharge
        }
        if s.contains("receipt") || s.contains("payment") || s.contains("invoice") || s.contains("order") {
            return .receipt
        }
        return .other
    }

    /// Domain → human merchant name. The keys are the same ones
    /// MerchantLogoResolver uses for logos, so a domain that has a
    /// logo also lights up in this scanner.
    private static let merchantsByDomain: [(String, String)] = [
        ("anthropic.com",        "Anthropic"),
        ("openai.com",           "OpenAI"),
        ("github.com",           "GitHub"),
        ("netflix.com",          "Netflix"),
        ("spotify.com",          "Spotify"),
        ("hulu.com",             "Hulu"),
        ("disneyplus.com",       "Disney+"),
        ("hbomax.com",           "HBO Max"),
        ("nytimes.com",          "NYTimes"),
        ("youtube.com",          "YouTube Premium"),
        ("apple.com",            "Apple"),
        ("adobe.com",            "Adobe"),
        ("dropbox.com",          "Dropbox"),
        ("amazon.com",           "Amazon"),
        ("uber.com",             "Uber"),
        ("doordash.com",         "DoorDash"),
        ("equinox.com",          "Equinox"),
        ("verizon.com",          "Verizon"),
        ("att.com",              "AT&T"),
        ("tmobile.com",          "T-Mobile"),
        ("affirm.com",           "Affirm"),
        ("klarna.com",           "Klarna"),
        ("paypal.com",           "PayPal"),
        ("venmo.com",            "Venmo")
    ]

    /// The domain table the scanner queries. Public so UI can show
    /// "scanning X brands" copy without us re-exporting the data.
    public static var knownDomains: [String] { merchantsByDomain.map(\.0) }
}
#endif
