import XCTest
@testable import OneCore

final class OneCoreTests: XCTestCase {
    func testQuestionLifecycleAndDeduplication() {
        var snapshot = Snapshot()
        let question = AgentEvent(id: "e1", agentID: "codex-1", kind: "question", provider: "Codex", text: "Which database?", choices: ["Postgres", "SQLite"], requestID: "r1")
        XCTAssertTrue(snapshot.apply(question))
        XCTAssertFalse(snapshot.apply(question))
        XCTAssertEqual(snapshot.agents.count, 1)
        XCTAssertEqual(snapshot.agents[0].state, .waiting)
        XCTAssertEqual(snapshot.agents[0].messages.count, 1)
        XCTAssertEqual(snapshot.agents[0].requestID, "r1")
        snapshot.apply(AgentEvent(agentID: "codex-1", kind: "working"))
        XCTAssertNil(snapshot.agents[0].requestID)
        XCTAssertTrue(snapshot.agents[0].choices.isEmpty)
        snapshot.apply(AgentEvent(agentID: "codex-1", kind: "done", text: "Done."))
        XCTAssertEqual(snapshot.agents[0].state, .done)
    }

    func testInvalidQuestionDoesNotCreateAgent() {
        var snapshot = Snapshot()
        XCTAssertFalse(snapshot.apply(AgentEvent(agentID: "x", kind: "question", text: "No reply id")))
        XCTAssertTrue(snapshot.agents.isEmpty)
        XCTAssertFalse(snapshot.apply(AgentEvent(agentID: "", kind: "done")))
        XCTAssertFalse(snapshot.apply(AgentEvent(agentID: "x", kind: "unknown")))
    }

    func testPersistenceRoundTripPreservesPendingQuestion() throws {
        var snapshot = Snapshot()
        snapshot.apply(AgentEvent(agentID: "a", kind: "question", text: "Continue?", choices: ["Yes", "No"], requestID: "q"))
        let loaded = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(loaded.agents, snapshot.agents)
        XCTAssertEqual(loaded.processedEventIDs, snapshot.processedEventIDs)
    }

    func testNewEventRestoresArchivedAgent() {
        var snapshot = Snapshot(agents: [Agent(id: "a", name: "a", archived: true)])
        snapshot.apply(AgentEvent(agentID: "a", kind: "done", text: "Finished"))
        XCTAssertFalse(snapshot.agents[0].archived)
    }

    func testRoutingRequiresUniqueMatch() {
        let snapshot = Snapshot(agents: [Agent(id: "web", name: "web", title: "Pricing page"), Agent(id: "api", name: "api", title: "Stripe checkout")])
        XCTAssertEqual(snapshot.suggestedAgent(for: "Fix pricing"), "web")
        XCTAssertNil(snapshot.suggestedAgent(for: "pricing stripe"))
        XCTAssertNil(snapshot.suggestedAgent(for: "hello"))
    }

    func testReplyFilenameCannotEscapeDirectory() {
        for input in ["../../file", "/tmp/secret", "unicode✓", "abc"] {
            let output = BridgePaths.safeFilename(input)
            XCTAssertFalse(output.contains("/"))
            XCTAssertFalse(output.contains("."))
        }
        XCTAssertEqual(BridgePaths.safeFilename("abc"), "YWJj")
    }
}
