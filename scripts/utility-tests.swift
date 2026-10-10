import Foundation
import OneCore

@MainActor func runUtilityTests(root: URL, check: (Bool, String) -> Void) throws {
    let folder = root.appendingPathComponent("utilities")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let utilities = Utilities(root: folder)
    utilities.updateNotes("Use the staging environment."); utilities.saveNotes()
    let loaded = Utilities(root: folder)
    check(loaded.notes == "Use the staging environment.", "notes survive reload")
    check(loaded.promptWithNotes("Run checks").contains("Use the staging environment."), "working memory accompanies managed requests")
    loaded.includeNotes = false; loaded.saveSettings()
    check(loaded.promptWithNotes("Run checks") == "Run checks", "notes can be excluded from requests")
    check(!Utilities(root: folder).includeNotes, "working memory preference survives reload")
    loaded.feedback = "The button did not open."; loaded.saveFeedback()
    check(Utilities(root: folder).feedback == loaded.feedback, "feedback draft survives reload")
    check(!loaded.feedbackReport().contains(folder.path), "feedback excludes local project and storage paths")
    let broken = root.appendingPathComponent("unreadable-notes")
    try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
    let invalid = Data([0xff, 0xfe, 0xff]); try invalid.write(to: broken.appendingPathComponent("notes.md"))
    let protected = Utilities(root: broken); protected.updateNotes("replacement"); protected.saveNotes()
    check(try Data(contentsOf: broken.appendingPathComponent("notes.md")) == invalid, "unreadable notes are never overwritten")
    let remoteFolder = root.appendingPathComponent("remote-utility-test")
    let store = Store(root: remoteFolder, demo: false)
    store.setDiscoveryEnabled(false)
    for dir in ["remote-commands", "remote-receipts"] { try FileManager.default.createDirectory(at: remoteFolder.appendingPathComponent(dir), withIntermediateDirectories: true) }
    try JSONSerialization.data(withJSONObject: ["generation": "test-generation"]).write(to: remoteFolder.appendingPathComponent("remote-connection.json"))
    store.snapshot.apply(AgentEvent(agentID: "qa", kind: "question", text: "Ready?", choices: ["Yes"], requestID: "current"))
    store.utilities.remoteRunning = true
    func command(request: String, generation: String = "test-generation") throws -> String {
        let id = UUID().uuidString
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "agentID": "qa", "requestID": request, "conversationKey": store.snapshot.agents[0].remoteConversationKey, "text": "Yes", "choiceIndex": 0, "createdAt": Date().timeIntervalSince1970, "generation": generation])
        try data.write(to: remoteFolder.appendingPathComponent("remote-commands/\(id).json"))
        return id
    }
    _ = try command(request: "stale"); store.pollRemoteCommands()
    check(store.pending == nil, "remote reply is revalidated against current question on the Mac")
    _ = try command(request: "current", generation: "revoked"); store.pollRemoteCommands()
    check(store.pending == nil, "commands from revoked connection generations are rejected")
    let immediate = try command(request: "current"); store.pollRemoteCommands()
    let immediateReceipt = try JSONSerialization.jsonObject(with: Data(contentsOf: remoteFolder.appendingPathComponent("remote-receipts/\(immediate).json"))) as! [String: Any]
    check(store.pending == nil && immediateReceipt["status"] as? String == "delivered", "remote reply commits through validated delivery immediately")
    store.undo()
    store.snapshot.apply(AgentEvent(agentID: "qa", kind: "question", text: "Ready?", choices: ["Yes"], requestID: "current"))
    let disabled = try command(request: "current"); store.utilities.remoteRunning = false; store.pollRemoteCommands()
    check(store.pending == nil, "disabled remote access cannot stage queued commands")
    try FileManager.default.removeItem(at: remoteFolder.appendingPathComponent("remote-commands/\(disabled).json"))
    store.utilities.remoteRunning = true
    let accepted = try command(request: "current"); store.pollRemoteCommands(); store.undo()
    let acceptedReceipt = try JSONSerialization.jsonObject(with: Data(contentsOf: remoteFolder.appendingPathComponent("remote-receipts/\(accepted).json"))) as! [String: Any]
    check(acceptedReceipt["status"] as? String == "delivered", "Mac Undo does not revoke an already confirmed phone delivery")
    store.snapshot.apply(AgentEvent(agentID: "qa", kind: "question", text: "Ready?", choices: ["Yes"], requestID: "current"))
    let changed = try command(request: "current")
    store.snapshot.agents[0].sessionID = "changed-session"
    store.pollRemoteCommands()
    let changedReceipt = try JSONSerialization.jsonObject(with: Data(contentsOf: remoteFolder.appendingPathComponent("remote-receipts/\(changed).json"))) as! [String: Any]
    check(changedReceipt["status"] as? String == "rejected", "remote recipient identity is fenced before immediate delivery")
    let delivered = try command(request: "current"); store.pollRemoteCommands(); store.commitPending()
    let deliveredReceipt = try JSONSerialization.jsonObject(with: Data(contentsOf: remoteFolder.appendingPathComponent("remote-receipts/\(delivered).json"))) as! [String: Any]
    check(deliveredReceipt["status"] as? String == "delivered", "remote bridge question receives delivery receipt after reply file is written")
    var resumable = Agent(id: "saved", name: "Saved", provider: "Claude", directory: root.path, state: .done, sessionID: "original", sourcePath: root.appendingPathComponent("history.jsonl").path)
    check(resumable.canReceiveRemotely, "saved Claude worktree conversation is eligible remotely")
    let identity = resumable.remoteConversationKey
    resumable.state = .working
    check(!resumable.canReceiveRemotely && resumable.remoteConversationKey == identity, "working Claude is blocked without changing recipient identity")
    resumable.provider = "Codex"; resumable.sessionID = UUID().uuidString
    check(resumable.canReceiveRemotely, "active Codex conversation can use native durable queue without a desktop integration")
    check(!resumable.remoteConversationKey.contains(root.path), "mobile recipient fence does not disclose filesystem paths")
    // Match the Mac's complete tracked list, including eligible saved sessions beyond row 40.
    store.snapshot.agents = (0..<75).map { index in
        Agent(id: "phone-\(index)", name: "Conversation \(index)", provider: index % 2 == 0 ? "Codex" : "Claude",
              directory: "/fixture/worktree-\(index)", state: .done, sessionID: "saved-\(index)", managed: true)
    }
    store.snapshot.agents[0].archived = true
    store.trackConversation("phone-1", enabled: false)
    store.pollRemoteCommands()
    let published = try JSONSerialization.jsonObject(with: Data(contentsOf: remoteFolder.appendingPathComponent("remote-state.json"))) as! [String: Any]
    let conversations = published["agents"] as! [[String: Any]]
    check(conversations.compactMap { $0["id"] as? String } == store.activeAgents.map(\.id) && conversations.count == 73,
          "phone publishes all Mac tracked conversations in the same order beyond forty")
    check(published["source"] as? String == "desktop" && store.utilities.remoteConversationCount == 73,
          "phone connection identifies the real desktop Store and its full tracked count")
    check(conversations.allSatisfy { $0["title"] as? String == $0["name"] as? String },
          "phone uses the Mac display-title fallback for conversations without a task title")
    check(conversations.contains { $0["id"] as? String == "phone-74" && $0["conversationKey"] as? String == store.agent(for: "phone-74")?.remoteConversationKey },
          "older phone conversation retains its exact saved provider session and worktree identity")
    let token = String(repeating: "x", count: 43)
    let appLink = PhoneConnection.appURL(from: URL(string: "https://mac.example/#\(token)")!)!
    let appComponents = URLComponents(url: appLink, resolvingAgainstBaseURL: false)!
    check(appComponents.scheme == "open-one" && appComponents.host == "" && appComponents.path == "/" &&
          appComponents.fragment == token && appComponents.queryItems == [URLQueryItem(name: "endpoint", value: "https://mac.example/")],
          "phone QR opens our installed app with the HTTPS origin and fragment credential")
    check(PhoneConnection.appURL(from: URL(string: "http://127.0.0.1:8088/#\(token)")!) == nil &&
          PhoneConnection.appURL(from: URL(string: "https://mac.example/path#\(token)")!) == nil &&
          PhoneConnection.appURL(from: URL(string: "https://user@mac.example/#\(token)")!) == nil,
          "native pairing QR refuses local previews, credentialed endpoints and routed URLs")
    store.shutdown(); utilities.shutdown(); loaded.shutdown()
}
