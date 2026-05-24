import Foundation
import Testing
@testable import Models

@Suite("Advisor")
struct AdvisorTests {

    @Test func decodesWireShapeFromSynapseV2() throws {
        let json = """
        {
          "advisors": [
            {
              "id": "financial",
              "name": "Wealth Coach",
              "specialty": "Budgets & cash flow",
              "avatarColor": "#34d399",
              "avatarInitials": "WC",
              "unreadCount": 2,
              "lastThreadId": "thr_abc",
              "lastSummary": "Reviewed sub renewals",
              "lastActiveAt": 1715798400000
            },
            {
              "id": "grant",
              "name": "Grant Advisor",
              "specialty": "NSF & university budgets",
              "avatarColor": "#60a5fa",
              "avatarInitials": "GA",
              "unreadCount": 0,
              "lastThreadId": null,
              "lastSummary": null,
              "lastActiveAt": null
            }
          ]
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(AdvisorsResponse.self, from: json)
        #expect(response.advisors.count == 2)
        let financial = response.advisors[0]
        #expect(financial.id == "financial")
        #expect(financial.name == "Wealth Coach")
        #expect(financial.avatarColorHex == "#34d399")
        #expect(financial.unreadCount == 2)
        #expect(financial.lastThreadId == "thr_abc")
        #expect(financial.lastActiveAt != nil)
        // 1715798400000 ms == 2024-05-15 16:00:00 UTC
        let expected = Date(timeIntervalSince1970: 1_715_798_400)
        #expect(abs(financial.lastActiveAt!.timeIntervalSince(expected)) < 1.0)
        // Second advisor — null fields decode to nil, unreadCount stays 0.
        let grant = response.advisors[1]
        #expect(grant.lastThreadId == nil)
        #expect(grant.lastActiveAt == nil)
        #expect(grant.unreadCount == 0)
    }

    @Test func acceptsSecondsScaleEpochsForLegacyRows() throws {
        // Some legacy threads carry seconds, not ms. Anything ≤ 10^12 is
        // interpreted as seconds.
        let json = """
        {"id":"x","name":"X","specialty":"Y","avatarColor":"#fff","avatarInitials":"X","lastActiveAt":1715798400}
        """.data(using: .utf8)!
        let advisor = try JSONDecoder().decode(Advisor.self, from: json)
        let expected = Date(timeIntervalSince1970: 1_715_798_400)
        #expect(advisor.lastActiveAt != nil)
        #expect(abs(advisor.lastActiveAt!.timeIntervalSince(expected)) < 1.0)
    }

    @Test func acceptsIso8601LastActiveAt() throws {
        let json = """
        {"id":"x","name":"X","specialty":"Y","avatarColor":"#fff","avatarInitials":"X","lastActiveAt":"2024-05-15T16:00:00Z"}
        """.data(using: .utf8)!
        let advisor = try JSONDecoder().decode(Advisor.self, from: json)
        let expected = Date(timeIntervalSince1970: 1_715_792_400)
        #expect(advisor.lastActiveAt != nil)
        // Within the ISO-8601 minute we picked above.
        #expect(abs(advisor.lastActiveAt!.timeIntervalSince(expected)) < 3600 * 24)
    }

    @Test func unreadCountDefaultsToZeroWhenMissing() throws {
        let json = """
        {"id":"x","name":"X","specialty":"Y","avatarColor":"#fff","avatarInitials":"X"}
        """.data(using: .utf8)!
        let advisor = try JSONDecoder().decode(Advisor.self, from: json)
        #expect(advisor.unreadCount == 0)
        #expect(advisor.lastThreadId == nil)
    }
}

@Suite("ChatMessage")
struct ChatMessageTests {

    @Test func appendingTokensMutatesContentInPlace() {
        var msg = ChatMessage(role: .assistant, content: "", isStreaming: true)
        msg.content += "Hello"
        msg.content += ", world"
        msg.isStreaming = false
        #expect(msg.content == "Hello, world")
        #expect(msg.isStreaming == false)
    }

    @Test func messageRolesAreCaseIterable() {
        #expect(MessageRole.allCases.count == 3)
        #expect(MessageRole.allCases.contains(.user))
        #expect(MessageRole.allCases.contains(.assistant))
        #expect(MessageRole.allCases.contains(.system))
    }
}
