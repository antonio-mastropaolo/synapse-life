import Foundation

/// Octagon Agents company snapshot for a vendor. Mirrors the
/// `brief` payload returned by synapse-v2's
/// `GET /api/finance/octagon/[vendor]` route. All numbers are USD millions
/// when present; `nil` means "Octagon did not return a value", not "$0".
public struct OctagonVendor: Sendable, Hashable, Identifiable, Decodable {

    public var id: String { vendor }

    public let vendor: String
    public let legalName: String?
    public let status: String?
    public let yearFounded: Int?
    public let employees: Int?
    public let hq: HQ
    public let primaryIndustry: String?
    public let verticals: [String]
    public let competitors: [String]
    /// Last valuation in USD millions.
    public let lastValuationUsdM: Decimal?
    public let lastValuationAt: Date?
    public let lastFinancing: Financing
    /// Total VC raised, USD millions.
    public let vcRaisedUsdM: Decimal?
    /// Revenue, USD millions.
    public let revenueUsdM: Decimal?
    public let ceo: CEO
    public let octagonUpdatedAt: Date?

    public init(
        vendor: String,
        legalName: String?,
        status: String?,
        yearFounded: Int?,
        employees: Int?,
        hq: HQ,
        primaryIndustry: String?,
        verticals: [String],
        competitors: [String],
        lastValuationUsdM: Decimal?,
        lastValuationAt: Date?,
        lastFinancing: Financing,
        vcRaisedUsdM: Decimal?,
        revenueUsdM: Decimal?,
        ceo: CEO,
        octagonUpdatedAt: Date?
    ) {
        self.vendor = vendor
        self.legalName = legalName
        self.status = status
        self.yearFounded = yearFounded
        self.employees = employees
        self.hq = hq
        self.primaryIndustry = primaryIndustry
        self.verticals = verticals
        self.competitors = competitors
        self.lastValuationUsdM = lastValuationUsdM
        self.lastValuationAt = lastValuationAt
        self.lastFinancing = lastFinancing
        self.vcRaisedUsdM = vcRaisedUsdM
        self.revenueUsdM = revenueUsdM
        self.ceo = ceo
        self.octagonUpdatedAt = octagonUpdatedAt
    }

    public struct HQ: Sendable, Hashable, Decodable {
        public let city: String?
        public let stateProvince: String?
        public let country: String?
        public init(city: String?, stateProvince: String?, country: String?) {
            self.city = city
            self.stateProvince = stateProvince
            self.country = country
        }
    }

    public struct Financing: Sendable, Hashable, Decodable {
        public let type: String?
        /// Round size in USD millions.
        public let sizeUsdM: Decimal?
        public let asOf: Date?

        public init(type: String?, sizeUsdM: Decimal?, asOf: Date?) {
            self.type = type
            self.sizeUsdM = sizeUsdM
            self.asOf = asOf
        }

        enum CodingKeys: String, CodingKey {
            case type
            case sizeUsd
            case asOf
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.type = try c.decodeIfPresent(String.self, forKey: .type)
            self.sizeUsdM = try c.decodeIfPresent(Double.self, forKey: .sizeUsd)
                .flatMap { Decimal(string: String($0)) }
            self.asOf = try c.decodeIfPresent(String.self, forKey: .asOf)
                .flatMap(OctagonVendor.parseDate)
        }
    }

    public struct CEO: Sendable, Hashable, Decodable {
        public let name: String?
        public let email: String?
        public init(name: String?, email: String?) {
            self.name = name
            self.email = email
        }
    }

    enum CodingKeys: String, CodingKey {
        case vendor
        case legalName
        case status
        case yearFounded
        case employees
        case hq
        case primaryIndustry
        case verticals
        case competitors
        case lastValuationUsd
        case lastValuationAt
        case lastFinancing
        case vcRaisedUsd
        case revenueUsd
        case ceo
        case octagonUpdatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.vendor = try c.decode(String.self, forKey: .vendor)
        self.legalName = try c.decodeIfPresent(String.self, forKey: .legalName)
        self.status = try c.decodeIfPresent(String.self, forKey: .status)
        self.yearFounded = try c.decodeIfPresent(Int.self, forKey: .yearFounded)
        self.employees = try c.decodeIfPresent(Int.self, forKey: .employees)
        self.hq = try c.decode(HQ.self, forKey: .hq)
        self.primaryIndustry = try c.decodeIfPresent(String.self, forKey: .primaryIndustry)
        self.verticals = try c.decodeIfPresent([String].self, forKey: .verticals) ?? []
        self.competitors = try c.decodeIfPresent([String].self, forKey: .competitors) ?? []
        self.lastValuationUsdM = try c.decodeIfPresent(Double.self, forKey: .lastValuationUsd)
            .flatMap { Decimal(string: String($0)) }
        self.lastValuationAt = try c.decodeIfPresent(String.self, forKey: .lastValuationAt)
            .flatMap(OctagonVendor.parseDate)
        self.lastFinancing = try c.decodeIfPresent(Financing.self, forKey: .lastFinancing)
            ?? Financing(type: nil, sizeUsdM: nil, asOf: nil)
        self.vcRaisedUsdM = try c.decodeIfPresent(Double.self, forKey: .vcRaisedUsd)
            .flatMap { Decimal(string: String($0)) }
        self.revenueUsdM = try c.decodeIfPresent(Double.self, forKey: .revenueUsd)
            .flatMap { Decimal(string: String($0)) }
        self.ceo = try c.decodeIfPresent(CEO.self, forKey: .ceo)
            ?? CEO(name: nil, email: nil)
        self.octagonUpdatedAt = try c.decodeIfPresent(String.self, forKey: .octagonUpdatedAt)
            .flatMap(OctagonVendor.parseDate)
    }

    fileprivate static func parseDate(_ s: String) -> Date? {
        // Server emits YYYY-MM-DD dates (no time component); pad to UTC
        // midnight before handing to the ISO parser.
        let padded = s.contains("T") ? s : "\(s)T00:00:00Z"
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: padded) { return d }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: padded)
    }

    public var headquartersDisplay: String {
        let parts = [hq.city, hq.stateProvince, hq.country].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "—" : parts.joined(separator: ", ")
    }
}

/// Wire envelope for the Octagon brief route. Forward-compat: the server's
/// "ok: false / error" branch surfaces as a decode failure that the
/// repository translates to `APIError.server`.
public struct OctagonBriefEnvelope: Decodable, Sendable {
    public let ok: Bool
    public let cached: Bool
    public let capturedAt: Date?
    public let brief: OctagonVendor

    enum CodingKeys: String, CodingKey {
        case ok, cached, capturedAt, brief
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? true
        self.cached = try c.decodeIfPresent(Bool.self, forKey: .cached) ?? false
        if let ms = try? c.decode(Int64.self, forKey: .capturedAt) {
            self.capturedAt = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        } else if let s = try? c.decode(Double.self, forKey: .capturedAt) {
            self.capturedAt = Date(timeIntervalSince1970: s / 1000.0)
        } else {
            self.capturedAt = nil
        }
        self.brief = try c.decode(OctagonVendor.self, forKey: .brief)
    }
}

// MARK: - Memberships

/// One recurring subscription / membership. The Memberships card on the web
/// renders these in a horizontally-scrollable swipe deck on phones and as a
/// list on desktop — we mirror that taxonomy here so the SwipeDeck view can
/// drive directly from `MembershipCard`.
public struct MembershipCard: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let vendor: String
    public let averageAmount: Decimal
    public let cadence: Cadence
    public let nextPredictedAt: Date?
    public let lastSeenAt: Date?
    public let confidence: Double
    public let status: Status

    public init(
        id: String,
        vendor: String,
        averageAmount: Decimal,
        cadence: Cadence,
        nextPredictedAt: Date?,
        lastSeenAt: Date?,
        confidence: Double,
        status: Status
    ) {
        self.id = id
        self.vendor = vendor
        self.averageAmount = averageAmount
        self.cadence = cadence
        self.nextPredictedAt = nextPredictedAt
        self.lastSeenAt = lastSeenAt
        self.confidence = confidence
        self.status = status
    }

    public enum Cadence: String, Sendable, Hashable, Codable, CaseIterable {
        case weekly
        case biweekly
        case monthly
        case quarterly
        case yearly
        case unknown

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self).lowercased()
            self = Cadence(rawValue: raw) ?? .unknown
        }

        /// Monthly-equivalent multiplier — used by the deck footer to surface
        /// total committed spend at a common scale.
        public var monthsPerCycle: Decimal {
            switch self {
            case .weekly:    return Decimal(string: "0.230769")! // 1/4.333
            case .biweekly:  return Decimal(string: "0.461538")!
            case .monthly:   return 1
            case .quarterly: return 3
            case .yearly:    return 12
            case .unknown:   return 1
            }
        }

        public var shortLabel: String {
            switch self {
            case .weekly:    return "wk"
            case .biweekly:  return "2wk"
            case .monthly:   return "mo"
            case .quarterly: return "qtr"
            case .yearly:    return "yr"
            case .unknown:   return "?"
            }
        }
    }

    public enum Status: String, Sendable, Hashable, Codable, CaseIterable {
        case active
        case canceled
        case paused
        case unknown

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self).lowercased()
            self = Status(rawValue: raw) ?? .unknown
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, vendor, averageAmount, cadence
        case nextPredictedAt, lastSeenAt, confidence, status
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.vendor = try c.decode(String.self, forKey: .vendor)
        let avg = try c.decode(Double.self, forKey: .averageAmount)
        self.averageAmount = Decimal(string: String(avg)) ?? Decimal(avg)
        self.cadence = try c.decode(Cadence.self, forKey: .cadence)
        self.nextPredictedAt = try c.decodeIfPresent(String.self, forKey: .nextPredictedAt)
            .flatMap(MembershipCard.parseDate)
        self.lastSeenAt = try c.decodeIfPresent(String.self, forKey: .lastSeenAt)
            .flatMap(MembershipCard.parseDate)
        self.confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 1.0
        self.status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .active
    }

    /// Monthly-equivalent commitment for this membership.
    public var monthlyEquivalent: Decimal {
        averageAmount / cadence.monthsPerCycle
    }

    fileprivate static func parseDate(_ s: String) -> Date? {
        let padded = s.contains("T") ? s : "\(s)T00:00:00Z"
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: padded) { return d }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: padded)
    }
}

/// Wire envelope for the memberships endpoint.
public struct MembershipsResponse: Decodable, Sendable {
    public let memberships: [MembershipCard]
    public let nextCursor: String?

    public init(memberships: [MembershipCard], nextCursor: String? = nil) {
        self.memberships = memberships
        self.nextCursor = nextCursor
    }
}
