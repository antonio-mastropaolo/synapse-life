import Foundation
import Testing
@testable import Models

@Suite("OctagonVendor")
struct OctagonVendorTests {

    @Test func decodesWireShapeFromSynapseV2() throws {
        let json = """
        {
          "ok": true,
          "cached": true,
          "capturedAt": 1715798400000,
          "brief": {
            "vendor": "anthropic",
            "legalName": "Anthropic, PBC",
            "status": "private",
            "yearFounded": 2021,
            "employees": 800,
            "hq": {"city":"San Francisco","stateProvince":"CA","country":"US"},
            "primaryIndustry": "AI / ML",
            "verticals": ["enterprise","developer-tools"],
            "competitors": ["OpenAI","Google DeepMind","Cohere"],
            "lastValuationUsd": 18400,
            "lastValuationAt": "2024-03-26",
            "lastFinancing": {"type":"Series C","sizeUsd":750,"asOf":"2024-03-26"},
            "vcRaisedUsd": 7900,
            "revenueUsd": 850,
            "ceo": {"name":"Dario Amodei","email":null},
            "octagonUpdatedAt": "2025-01-15"
          }
        }
        """.data(using: .utf8)!
        let envelope = try JSONDecoder().decode(OctagonBriefEnvelope.self, from: json)
        #expect(envelope.ok == true)
        #expect(envelope.cached == true)
        let v = envelope.brief
        #expect(v.vendor == "anthropic")
        #expect(v.legalName == "Anthropic, PBC")
        #expect(v.yearFounded == 2021)
        #expect(v.employees == 800)
        #expect(v.hq.city == "San Francisco")
        #expect(v.hq.country == "US")
        #expect(v.headquartersDisplay == "San Francisco, CA, US")
        #expect(v.competitors.count == 3)
        // 18400 USD millions → $18.4B
        #expect(v.lastValuationUsdM == Decimal(string: "18400.0"))
        #expect(v.lastFinancing.type == "Series C")
        #expect(v.lastFinancing.sizeUsdM == Decimal(string: "750.0"))
        #expect(v.revenueUsdM == Decimal(string: "850.0"))
        #expect(v.ceo.name == "Dario Amodei")
        #expect(v.ceo.email == nil)
    }

    @Test func unknownFieldsAndAbsentArraysDecodeAsEmpty() throws {
        let json = """
        {
          "brief": {
            "vendor": "x",
            "hq": {"city":null,"stateProvince":null,"country":null}
          }
        }
        """.data(using: .utf8)!
        let envelope = try JSONDecoder().decode(OctagonBriefEnvelope.self, from: json)
        let v = envelope.brief
        #expect(v.vendor == "x")
        #expect(v.verticals.isEmpty)
        #expect(v.competitors.isEmpty)
        #expect(v.headquartersDisplay == "—")
        #expect(v.lastFinancing.type == nil)
        #expect(v.lastFinancing.sizeUsdM == nil)
    }
}

@Suite("MembershipCard")
struct MembershipCardTests {

    @Test func decodesMembershipsList() throws {
        let json = """
        {
          "memberships": [
            {
              "id": "m_001",
              "vendor": "Netflix",
              "averageAmount": 15.49,
              "cadence": "monthly",
              "nextPredictedAt": "2026-06-04",
              "lastSeenAt": "2026-05-04",
              "confidence": 0.97,
              "status": "active"
            },
            {
              "id": "m_002",
              "vendor": "Costco",
              "averageAmount": 60.00,
              "cadence": "yearly",
              "nextPredictedAt": null,
              "lastSeenAt": "2025-11-12",
              "confidence": 0.85,
              "status": "active"
            }
          ]
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(MembershipsResponse.self, from: json)
        #expect(response.memberships.count == 2)
        let netflix = response.memberships[0]
        #expect(netflix.vendor == "Netflix")
        #expect(netflix.averageAmount == Decimal(string: "15.49"))
        #expect(netflix.cadence == .monthly)
        #expect(netflix.monthlyEquivalent == Decimal(string: "15.49"))

        let costco = response.memberships[1]
        #expect(costco.cadence == .yearly)
        // Yearly $60 → ~$5/mo
        #expect(costco.monthlyEquivalent == Decimal(string: "5"))
    }

    @Test func unknownCadenceDecodesAsUnknownInsteadOfFailing() throws {
        let json = """
        {"id":"x","vendor":"X","averageAmount":1.0,"cadence":"fortnightly"}
        """.data(using: .utf8)!
        let card = try JSONDecoder().decode(MembershipCard.self, from: json)
        #expect(card.cadence == .unknown)
        #expect(card.status == .active)
    }

    @Test func weeklyCadenceProducesPlausibleMonthlyEquivalent() {
        let card = MembershipCard(
            id: "x", vendor: "Y",
            averageAmount: Decimal(string: "10.00")!,
            cadence: .weekly,
            nextPredictedAt: nil, lastSeenAt: nil,
            confidence: 1.0, status: .active
        )
        let monthly = card.monthlyEquivalent
        // $10/wk * 4.333 ≈ $43.33
        let asDouble = NSDecimalNumber(decimal: monthly).doubleValue
        #expect(asDouble > 42.0)
        #expect(asDouble < 45.0)
    }
}
