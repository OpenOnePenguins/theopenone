import Foundation
import OneCore

@MainActor func runPhoneDeliveryTests(root: URL, check: (Bool, String) -> Void) throws {
    let directory = root.appendingPathComponent("phone-delivery")
    let store = Store(root: directory, demo: false)
    store.setDiscoveryEnabled(false)
    defer { store.shutdown() }
    let fm = FileManager.default
    for folder in ["remote-commands", "remote-receipts"] {
        try fm.createDirectory(at: directory.appendingPathComponent(folder), withIntermediateDirectories: true)
    }
    let generation = UUID().uuidString
    try JSONSerialization.data(withJSONObject: ["generation": generation]).write(to: directory.appendingPathComponent("remote-connection.json"))
    store.utilities.remoteRunning = true
    func question(_ request: String) {
        store.snapshot.apply(AgentEvent(agentID: "phone", kind: "question", text: "Fixture question", requestID: request))
    }
    func command(_ request: String, key: String? = nil, created: Double = Date().timeIntervalSince1970) throws -> String {
        let id = UUID().uuidString
        let body: [String: Any] = ["id": id, "generation": generation, "createdAt": created,
            "agentID": "phone", "requestID": request, "conversationKey": key ?? store.snapshot.agents.first(where: { $0.id == "phone" })!.remoteConversationKey,
            "text": "Phone fixture answer"]
        try JSONSerialization.data(withJSONObject: body).write(to: directory.appendingPathComponent("remote-commands/\(id).json"), options: .atomic)
        return id
    }
    func receipt(_ id: String) throws -> String? {
        let data = try Data(contentsOf: directory.appendingPathComponent("remote-receipts/\(id).json"))
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["status"] as? String
    }
    func replyExists(_ request: String) -> Bool {
        fm.fileExists(atPath: directory.appendingPathComponent("replies/\(BridgePaths.safeFilename(request)).json").path)
    }
    question("phone-now")
    store.selection = "phone"; store.draft = "Keep this Mac draft"
    let immediate = try command("phone-now")
    store.pollRemoteCommands()
    check(replyExists("phone-now") && store.pending == nil, "phone Send delivers in one poll without the Mac Undo delay")
    check(try receipt(immediate) == "delivered", "phone delivery receipt reflects actual accepted reply")
    check(store.draft == "Keep this Mac draft", "phone delivery preserves the Mac composer draft")
    let published = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("remote-state.json"))) as! [String: Any]
    let agents = published["agents"] as! [[String: Any]]
    check((agents.first?["messages"] as? [[String: Any]])?.last?["text"] as? String == "Phone fixture answer", "phone history publishes the sent message in the same poll")

    question("stale-question")
    let stale = try command("stale-question")
    try JSONEncoder().encode(AgentEvent(agentID: "phone", kind: "question", text: "Replacement", requestID: "replacement")).write(to: directory.appendingPathComponent("events/phone-replacement.json"))
    store.pollRemoteCommands()
    check(try receipt(stale) == "rejected" && !replyExists("stale-question") && store.selected?.requestID == "replacement", "immediate phone delivery revalidates replacement questions before writing")
    let wrongSession = try command("replacement", key: "different-session")
    store.pollRemoteCommands()
    check(try receipt(wrongSession) == "rejected" && !replyExists("replacement"), "phone fast path rejects a changed session/worktree identity")
    let expired = try command("replacement", created: Date().timeIntervalSince1970 - 31)
    store.pollRemoteCommands()
    check(try receipt(expired) == "rejected" && !replyExists("replacement"), "expired phone operations never deliver")

    store.stage("Mac answer")
    check(store.pending != nil && store.pending!.deadline.timeIntervalSinceNow > 1.5 && !replyExists("replacement"), "Mac composer keeps its two-second Undo window")
    let busy = try command("replacement")
    store.pollRemoteCommands()
    check(try receipt(busy) == "rejected" && store.pending?.text == "Mac answer", "phone Send cannot replace an existing Mac pending reply")
    store.undo()
    check(!replyExists("replacement"), "Mac Undo still prevents delivery after a rejected phone send")
}

@MainActor func runStoreRegressionTests(root: URL, check: (Bool, String) -> Void) throws {
    let directory = root.appendingPathComponent("composer-regressions")
    let store = Store(root: directory, demo: false)
    func question(_ id: String, _ request: String) {
        store.snapshot.apply(AgentEvent(agentID: id, kind: "question", text: "Question", requestID: request))
    }
    question("a", "a1"); question("b", "b1")
    store.selection = "a"
    store.draft = "Draft A"
    let aKey = store.composerKey
    store.selection = "b"
    check(store.draft.isEmpty, "Inbox selection does not carry another recipient's draft")
    store.draft = "Draft B"
    let imageB = root.appendingPathComponent("b.png")
    store.attachment = imageB
    store.selection = "a"
    check(store.draft == "Draft A" && store.attachment == nil, "Inbox restores recipient-specific text and attachment")
    store.stage(store.draft)
    store.selection = "b"
    store.commitPending()
    check(store.draft == "Draft B" && store.attachment == imageB && store.draft(for: aKey).isEmpty, "delivery clears captured composer without disturbing current recipient")
    let delivered = try JSONDecoder().decode(AgentReply.self, from: Data(contentsOf: directory.appendingPathComponent("replies/\(BridgePaths.safeFilename("a1")).json")))
    check(delivered.agentID == "a" && delivered.text == "Draft A", "changing selection during undo never retargets delivery")
    store.tab = "Talk"
    store.draft = "Shared Talk draft"
    store.selection = "a"
    store.selection = "b"
    check(store.draft == "Shared Talk draft" && store.attachment == nil, "Talk preserves its shared routing draft without Inbox attachment")
    store.stage(store.draft)
    store.draft = "Edited while pending"
    store.commitPending()
    check(store.draft == "Edited while pending", "successful delivery preserves newer composer edits")
    question("a", "a2")
    store.selection = "a"
    store.stage(store.draft)
    store.undo()
    check(store.pending == nil && store.draft == "Edited while pending", "undo preserves unsent composer contents")
    store.tab = "Inbox"
    store.setDraft("Dictated to A", for: aKey)
    store.selection = "b"
    check(store.draft == "Draft B" && store.draft(for: aKey) == "Dictated to A", "captured dictation key updates original recipient only")
    store.createAgent(provider: "Codex", directory: root.path, prompt: "Initial task")
    store.undo()
    check(store.draft == "Initial task" && store.selected?.state == .idle, "undo of new-session send retains initial task for editing")
    store.snapshot.agents.append(Agent(id: "running", name: "running", provider: "Codex", state: .working, sessionID: "saved-session", managed: true))
    store.snapshot.agents.append(Agent(id: "archived", name: "archived", state: .done, archived: true))
    check(store.archivedAgents.map(\.id) == ["archived"], "cleared conversations remain available for restoration")
    store.restoreAgent("archived")
    check(store.selected?.id == "archived" && store.selected?.archived == false, "restore a cleared conversation and select it")
    store.shutdown()
    let restored = Store(root: directory, demo: false)
    restored.selection = "a"
    check(restored.draft == "Dictated to A", "recipient drafts survive restart")
    restored.selection = "b"
    check(restored.draft == "Draft B" && restored.attachment == imageB, "recipient attachments survive restart")
    restored.tab = "Talk"
    check(restored.draft == "Edited while pending", "shared Talk draft survives restart separately")
    let running = restored.snapshot.agents.first { $0.id == "running" }
    check(running?.state == .offline && running?.sessionID == "saved-session", "restart marks owned process offline while preserving resumable session")
    restored.shutdown()
    // Metadata-only integration fixtures: demo mode never invokes the Herdr CLI.
    let herdr = Store(root: root.appendingPathComponent("herdr-mapping"), demo: true)
    herdr.snapshot = Snapshot()
    herdr.connectHerdr(session: "fixture")
    let idle = try JSONDecoder().decode(HerdrAgent.self, from: Data(#"{"pane_id":"w1:p1","terminal_id":"term-1","agent_status":"idle","agent":"codex","name":"fixture-agent","cwd":"/fixture"}"#.utf8))
    herdr.mergeHerdr([idle], session: "wrong-session")
    check(herdr.snapshot.agents.isEmpty, "ignore inventory from a previously connected Herdr session")
    herdr.mergeHerdr([idle], session: "fixture")
    let original = herdr.snapshot.agents[0]
    check(original.isHerdr && original.canReceive && original.herdrTerminalID == "term-1", "map explicit live Herdr agent into a reply-capable card")
    let blocked = try JSONDecoder().decode(HerdrAgent.self, from: Data(#"{"pane_id":"w1:p1","terminal_id":"term-1","agent_status":"blocked","agent":"codex"}"#.utf8))
    herdr.mergeHerdr([blocked], session: "fixture")
    herdr.selection = original.id
    herdr.stage("Do not answer an approval as a prompt")
    check(herdr.selected?.state == .waiting && herdr.selected?.canReceive == false && herdr.pending == nil, "blocked Herdr terminal refuses generic prompt input")
    let replacement = try JSONDecoder().decode(HerdrAgent.self, from: Data(#"{"pane_id":"w1:p1","terminal_id":"term-2","agent_status":"idle","agent":"claude"}"#.utf8))
    herdr.mergeHerdr([replacement], session: "fixture")
    check(herdr.snapshot.agents.count == 2 && herdr.selected?.herdrConnected == false && herdr.selected?.state == .offline, "replacement terminal never inherits old agent identity")
    herdr.connectHerdr(session: nil)
    check(herdr.snapshot.agents.allSatisfy { !$0.canReceive && $0.state == .offline }, "disconnect removes every Herdr reply channel")
    let roundtrip = try JSONDecoder().decode(Agent.self, from: JSONEncoder().encode(original))
    check(roundtrip.herdrSession == "fixture" && roundtrip.herdrPaneID == "w1:p1", "persist Herdr target identity with agent")
    herdr.shutdown()
    check(!AgentEvent(id: "", agentID: "a", kind: "message").isValid, "empty event identity is rejected")
    check(!AgentEvent(agentID: "a", kind: "question", text: "Question", requestID: "  ").isValid, "empty question request identity is rejected")
}
