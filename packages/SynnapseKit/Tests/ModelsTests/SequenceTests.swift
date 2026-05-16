import Foundation
import Testing
@testable import Models

@Suite("Sequence — model")
struct SequenceTests {

    @Test
    func decodesServerRowWithKnownStatus() throws {
        let json = """
        {
          "total": 1,
          "sequences": [{
            "id": "seq-1",
            "opportunity_id": "opp-1",
            "lead_email": "lead@example.com",
            "lead_display": "Lead Name",
            "subject": "Hello",
            "touch1_body": "Hi there",
            "current_touch": 1,
            "last_sent_at": 1739625600.0,
            "next_due_at": 1739712000.0,
            "status": "active",
            "last_log": null,
            "created_at": 1739625500.0
          }]
        }
        """.data(using: .utf8)!
        let envelope = try JSONDecoder().decode(ServerSequencesListResponse.self, from: json)
        #expect(envelope.total == 1)
        #expect(envelope.sequences.count == 1)
        let projected = Sequence.fromServerRow(envelope.sequences[0])
        #expect(projected.id == "seq-1")
        #expect(projected.status == .active)
        #expect(projected.stages.count == 3)
        #expect(projected.stages[0].touchNumber == 1)
        #expect(projected.stages[0].status == .sent)
        #expect(projected.stages[1].status == .draft)
        #expect(projected.stages[2].status == .draft)
        #expect(projected.activeStage?.touchNumber == 1)
    }

    @Test
    func unknownStatusFallsBackInsteadOfThrowing() throws {
        let json = """
        {
          "total": 1,
          "sequences": [{
            "id": "seq-x",
            "opportunity_id": "opp-x",
            "lead_email": "x@example.com",
            "lead_display": "X",
            "subject": "S",
            "touch1_body": "B",
            "current_touch": 0,
            "last_sent_at": null,
            "next_due_at": null,
            "status": "future-state-from-server",
            "last_log": null,
            "created_at": 1739625500.0
          }]
        }
        """.data(using: .utf8)!
        let envelope = try JSONDecoder().decode(ServerSequencesListResponse.self, from: json)
        let projected = Sequence.fromServerRow(envelope.sequences[0])
        #expect(projected.status == .unknown)
    }

    @Test
    func activeStageClampsToValidRange() {
        let stage1 = SequenceStage(
            id: "s1", touchNumber: 1, dayOffset: 0,
            channel: .email, subject: "A", body: "B", status: .sent
        )
        let stage2 = SequenceStage(
            id: "s2", touchNumber: 2, dayOffset: 3,
            channel: .email, subject: "", body: "", status: .draft
        )
        let seq = Sequence(
            id: "s", opportunityId: "o", leadEmail: "e", leadDisplay: "L",
            subject: "S", stages: [stage1, stage2], currentTouch: 99,
            lastSentAt: nil, nextDueAt: nil, status: .active,
            lastLog: nil, createdAt: Date(timeIntervalSince1970: 0)
        )
        #expect(seq.activeStage?.touchNumber == 2)
    }

    @Test
    func activeStageReturnsNilWhenNoStages() {
        let seq = Sequence(
            id: "s", opportunityId: "o", leadEmail: "e", leadDisplay: "L",
            subject: "S", stages: [], currentTouch: 1,
            lastSentAt: nil, nextDueAt: nil, status: .active,
            lastLog: nil, createdAt: Date(timeIntervalSince1970: 0)
        )
        #expect(seq.activeStage == nil)
    }

    @Test
    func currentTouchZeroLeavesAllStagesDraftAfterFirst() throws {
        let json = """
        {
          "total": 1,
          "sequences": [{
            "id": "seq-z",
            "opportunity_id": "opp-z",
            "lead_email": "z@example.com",
            "lead_display": "Z",
            "subject": "S",
            "touch1_body": "B",
            "current_touch": 0,
            "last_sent_at": null,
            "next_due_at": null,
            "status": "active",
            "last_log": null,
            "created_at": 1739625500.0
          }]
        }
        """.data(using: .utf8)!
        let envelope = try JSONDecoder().decode(ServerSequencesListResponse.self, from: json)
        let projected = Sequence.fromServerRow(envelope.sequences[0])
        #expect(projected.stages[0].status == .queued)
        #expect(projected.stages[1].status == .draft)
        #expect(projected.stages[2].status == .draft)
    }

    @Test
    func unknownChannelDecodesAsUnknown() throws {
        let raw = "\"smoke-signal\"".data(using: .utf8)!
        let channel = try JSONDecoder().decode(SequenceChannel.self, from: raw)
        #expect(channel == .unknown)
    }

    @Test
    func unknownStageStatusDecodesAsUnknown() throws {
        let raw = "\"in-flight\"".data(using: .utf8)!
        let status = try JSONDecoder().decode(SequenceStageStatus.self, from: raw)
        #expect(status == .unknown)
    }
}
