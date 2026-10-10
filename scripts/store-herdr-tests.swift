import Foundation
import OneCore

@MainActor func runStoreHerdrTests(root: URL, check: (Bool, String) -> Void) async throws {
    let fixture = root.appendingPathComponent("store-herdr-fixture")
    try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    let executable = fixture.appendingPathComponent("herdr-fixture")
    let mode = fixture.appendingPathComponent("mode")
    let delivery = fixture.appendingPathComponent("delivered")
    let keys = fixture.appendingPathComponent("keys")
    try #"""
    #!/bin/sh
    fixture_dir=$(dirname "$0")
    mode=$(cat "$fixture_dir/mode")
    first='{"pane_id":"w1:p1","terminal_id":"term-1","agent_status":"idle","agent":"codex","name":"first","cwd":"/fixture","agent_session":{"source":"codex","agent":"codex","kind":"session_id","value":"native-one"}}'
    second='{"pane_id":"w1:p2","terminal_id":"term-2","agent_status":"idle","agent":"claude","name":"second","cwd":"/fixture"}'
    if [ "$mode" = 'blocked' ]; then
      first='{"pane_id":"w1:p1","terminal_id":"term-1","agent_status":"blocked","agent":"codex","name":"first","cwd":"/fixture","agent_session":{"source":"codex","agent":"codex","kind":"session_id","value":"native-one"}}'
      second='{"pane_id":"w1:p2","terminal_id":"term-2","agent_status":"blocked","agent":"claude","name":"second","cwd":"/fixture"}'
    fi
    case "$4" in
      list) printf '{"result":{"type":"agent_list","agents":[%s,%s]}}\n' "$first" "$second" ;;
      get)
        if [ "$5" = 'w1:p2' ]; then selected="$second"; else selected="$first"; fi
        printf '{"result":{"type":"agent_info","agent":%s}}\n' "$selected" ;;
      prompt)
        if [ "$mode" = 'prompt-fail' ]; then printf '%s\n' 'fixture delivery failure' >&2; exit 1; fi
        printf '%s\n' "$5" >> "$fixture_dir/delivered"
        printf '{"result":{"type":"agent_prompted","agent":%s}}\n' "$first" ;;
      read)
        if [ "$mode" = 'slow-read-fail' ]; then sleep 1; fi
        if [ "$mode" = 'read-fail' ] || [ "$mode" = 'slow-read-fail' ]; then printf '%s\n' 'fixture read failure' >&2; exit 1; fi
        printf 'Output from %s\n' "$5" ;;
      send-keys)
        printf '%s %s\n' "$5" "$6" >> "$fixture_dir/keys"
        printf '%s\n' '{"result":{"type":"ok"}}' ;;
      *) exit 2 ;;
    esac
    """#.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    try "ok".write(to: mode, atomically: true, encoding: .utf8)
    let store = Store(root: fixture.appendingPathComponent("data"), demo: false, herdrService: HerdrService(executableOverride: executable))
    defer { store.shutdown() }
    store.connectHerdr(session: "fixture")
    for _ in 0..<100 {
        if store.snapshot.agents.count == 2 && !store.herdrRefreshing { break }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    guard let first = store.snapshot.agents.first(where: { $0.herdrPaneID == "w1:p1" }), let second = store.snapshot.agents.first(where: { $0.herdrPaneID == "w1:p2" }) else {
        throw NSError(domain: "StoreHerdrTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture did not connect"])
    }
    store.selection = first.id
    let transcript = Agent(id: "observed:codex:native-one", name: "observed", provider: "Codex", directory: "/fixture", title: "Existing conversation", messages: [Message(role: "assistant", text: "Original history")], sessionID: "native-one", sourcePath: "/fixture/native-one.jsonl")
    store.mergeDiscovered(DiscoveryResult(agents: [transcript]))
    check(store.activeAgents.count == 2 && store.selected?.title == transcript.title && store.selected?.canReceive == true, "fixture transport gains observed history before real subprocess delivery")
    await store.refreshHerdr(readAgentID: second.id)
    check(store.herdrOutputs[second.id] == "Output from w1:p2\n" && store.selection == first.id, "popout reads its terminal without changing selected agent")
    check(store.herdrReadTimes[second.id] != nil, "terminal snapshots expose successful read time")
    store.draft = "Fixture delayed task"
    store.stage(store.draft)
    try await Task.sleep(nanoseconds: 200_000_000)
    check(!FileManager.default.fileExists(atPath: delivery.path), "Herdr prompt is not delivered during undo window")
    store.undo()
    try await Task.sleep(nanoseconds: 2_100_000_000)
    check(!FileManager.default.fileExists(atPath: delivery.path) && store.draft == "Fixture delayed task", "Herdr undo prevents submission and preserves draft")
    store.stage(store.draft)
    for _ in 0..<100 {
        if store.snapshot.agents.first(where: { $0.id == first.id })?.messages.last?.text == "Fixture delayed task", !store.herdrRefreshing, store.selected?.state == .idle { break }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    let submitted = (try? String(contentsOf: delivery, encoding: .utf8)) ?? ""
    check(submitted == "w1:p1\n" && store.draft.isEmpty, "delayed Herdr prompt reaches captured pane exactly once and clears confirmed draft")
    await store.refreshHerdr()
    try "prompt-fail".write(to: mode, atomically: true, encoding: .utf8)
    store.draft = "Keep this after failure"
    store.stage(store.draft)
    store.commitPending()
    for _ in 0..<100 {
        if store.selected?.state == .offline { break }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    check(store.draft == "Keep this after failure" && store.selected?.herdrConnected == false && store.selected?.state == .offline, "unconfirmed Herdr delivery preserves draft and disables live reply channel")
    check((try? String(contentsOf: delivery, encoding: .utf8)) == submitted, "Herdr delivery failure never triggers automatic retry")
    try "ok".write(to: mode, atomically: true, encoding: .utf8)
    await store.refreshHerdr(readAgentID: second.id)
    try "read-fail".write(to: mode, atomically: true, encoding: .utf8)
    await store.refreshHerdr(readAgentID: second.id)
    check(store.herdrOutputs[second.id] == nil && store.herdrReadTimes[second.id] == nil, "failed terminal refresh removes stale snapshot and timestamp")
    try "blocked".write(to: mode, atomically: true, encoding: .utf8)
    await store.refreshHerdr(readAgentID: second.id)
    store.stageTerminalKey("down", agentID: second.id)
    check(store.pending?.agentID == second.id && store.pending?.terminalKey == "down" && store.pending?.composerKey == nil, "approval key captures explicit popout target without a composer")
    try await Task.sleep(nanoseconds: 200_000_000)
    check(!FileManager.default.fileExists(atPath: keys.path), "approval key observes undo delay before writing terminal input")
    store.undo()
    try await Task.sleep(nanoseconds: 2_100_000_000)
    check(!FileManager.default.fileExists(atPath: keys.path), "undo prevents terminal approval key delivery")
    store.stageTerminalKey("enter", agentID: second.id)
    for _ in 0..<100 {
        if store.snapshot.agents.first(where: { $0.id == second.id })?.messages.last?.text == "Sent terminal key: enter.", !store.herdrRefreshing { break }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    let keyReceipt = store.snapshot.agents.first { $0.id == second.id }?.messages.last
    check((try? String(contentsOf: keys, encoding: .utf8)) == "w1:p2 enter\n" && keyReceipt?.role == "system" && store.selection == first.id && store.draft == "Keep this after failure", "confirmed approval key reaches exact pane and keeps unrelated draft")
    store.stageTerminalKey("esc", agentID: second.id)
    if let index = store.snapshot.agents.firstIndex(where: { $0.id == second.id }) { store.snapshot.agents[index].herdrIdentity = "replacement-identity" }
    store.commitPending()
    check((try? String(contentsOf: keys, encoding: .utf8)) == "w1:p2 enter\n" && store.pending == nil, "changed terminal identity rejects pending approval key")
    try "slow-read-fail".write(to: mode, atomically: true, encoding: .utf8)
    let staleRefresh = Task { await store.refreshHerdr(readAgentID: second.id) }
    try await Task.sleep(nanoseconds: 150_000_000)
    store.connectHerdr(session: nil)
    await staleRefresh.value
    check(store.herdrNotice == nil && store.herdrSession == nil && store.herdrOutputs.isEmpty, "read failure from old connection cannot overwrite disconnected state")
    try runHerdrConversationTests(root: root, executable: executable, check: check)
}

@MainActor private func runHerdrConversationTests(root: URL, executable: URL, check: (Bool, String) -> Void) throws {
    let now = Date()
    let message = Message(role: "user", text: "Fix the checkout", id: "original", date: now.addingTimeInterval(-1))
    let observed = Agent(id: "observed:codex:native-one", name: "codex-one", provider: "Codex", directory: "/project/worktree", state: .unknown, title: "Checkout fix", messages: [message], sessionID: "native-one", updatedAt: now, sourcePath: "/fixture/one.jsonl")
    func live(_ native: String = "native-one", pane: String = "w1:p1", terminal: String = "term-1", status: String = "idle", provider: String = "codex", kind: String = "session_id", sessionProvider: String? = nil) throws -> HerdrAgent {
        let value: [String: Any] = ["pane_id": pane, "terminal_id": terminal, "agent_status": status, "agent": provider, "title": "Terminal title", "cwd": "/project/worktree", "agent_session": ["source": "fixture", "agent": sessionProvider ?? provider, "kind": kind, "value": native]]
        return try JSONDecoder().decode(HerdrAgent.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func makeStore(_ name: String) -> Store {
        let store = Store(root: root.appendingPathComponent(name), herdrService: HerdrService(executableOverride: executable))
        store.connectHerdr(session: "fixture")
        return store
    }
    let store = makeStore("herdr-conversations")
    defer { store.shutdown() }
    store.mergeDiscovered(DiscoveryResult(agents: [observed]))
    store.selection = observed.id
    store.draft = "Continue this exact conversation"
    store.mergeHerdr([try live()], session: "fixture")
    guard let joined = store.selected else { throw HerdrError.invalidResponse }
    check(store.activeAgents.count == 1 && joined.isHerdr && !joined.isObserved && joined.canReceive, "transcript and live session become one directly replyable chat")
    check(joined.title == observed.title && joined.messages == observed.messages && joined.sourcePath == observed.sourcePath, "live chat keeps transcript title and history")
    check(store.draft == "Continue this exact conversation" && store.draft(for: "agent:" + observed.id) == store.draft, "joining preserves selected draft and existing popout draft address")
    check(store.agent(for: observed.id)?.id == joined.id, "existing popout resolves joined conversation")
    store.stage("Continue this exact conversation", agentID: observed.id, composerKeyOverride: "agent:" + observed.id)
    check(store.pending?.agentID == joined.id && store.pending?.terminalIdentity == joined.herdrIdentity, "old conversation address stages against exact live terminal identity")
    store.undo()
    store.setDiscoveryEnabled(false)
    check(store.activeAgents.count == 1, "discovery toggle does not hide connected transcript-backed chats")
    store.setDiscoveryEnabled(true)
    var newer = observed; newer.title = "Updated checkout title"; newer.updatedAt = now.addingTimeInterval(1)
    newer.messages.append(Message(role: "assistant", text: "Checkout fixed", id: "answer", date: now))
    store.mergeHerdr([try live(status: "working")], session: "fixture")
    store.mergeDiscovered(DiscoveryResult(agents: [newer]))
    check(store.selected?.state == .working && store.selected?.title == newer.title && store.selected?.messages == newer.messages, "transcript refresh updates history without overwriting live status")
    store.mergeDiscovered(DiscoveryResult(agents: [observed]))
    check(store.selected?.title == newer.title && store.activeAgents.count == 1, "older transcript cannot regress joined history or recreate duplicate")
    store.mergeHerdr([try live()], session: "fixture")
    store.stage(store.draft)
    let pendingIdentity = store.pending?.terminalIdentity
    store.mergeHerdr([try live(pane: "w2:p3", terminal: "term-new")], session: "fixture")
    check(store.selected?.id == joined.id && store.selected?.herdrPaneID == "w2:p3" && store.activeAgents.count == 1, "unique native conversation keeps stable chat identity after pane move")
    check(store.pending?.terminalIdentity == pendingIdentity && store.selected?.herdrIdentity != pendingIdentity, "pane move cannot silently retarget staged reply")
    store.commitPending()
    check(store.pending == nil && store.notice?.contains("no longer ready") == true && !store.draft.isEmpty, "staged reply is rejected when terminal identity moves")
    store.mergeHerdr([try live("replacement", pane: "w2:p3", terminal: "term-new")], session: "fixture")
    let replacement = store.activeAgents.first { $0.sessionID == "replacement" }
    check(replacement?.messages.isEmpty == true && replacement?.id != joined.id && store.selected?.herdrConnected == false, "new conversation in same terminal cannot inherit history or draft")
    store.connectHerdr(session: nil)
    store.mergeDiscovered(DiscoveryResult(agents: [newer]))
    check(store.selected?.canReceive == false && store.selected?.state == .offline && store.selected?.messages == newer.messages, "disconnected transcript refresh cannot reactivate terminal control")
    store.shutdown()
    let restored = Store(root: store.root, herdrService: HerdrService(executableOverride: executable))
    defer { restored.shutdown() }
    check(restored.snapshot.agents.first { $0.id == joined.id }?.sourcePath == observed.sourcePath && restored.draft(for: "agent:" + joined.id) == "Continue this exact conversation", "joined history and migrated draft survive restart")

    let reverse = makeStore("herdr-before-discovery")
    defer { reverse.shutdown() }
    reverse.mergeHerdr([try live()], session: "fixture")
    let originalID = reverse.activeAgents.first?.id
    reverse.mergeDiscovered(DiscoveryResult(agents: [observed]))
    check(reverse.activeAgents.count == 1 && reverse.activeAgents.first?.id == originalID && reverse.activeAgents.first?.messages == observed.messages, "Herdr-first arrival joins later transcript without replacing live chat")

    let ambiguous = makeStore("herdr-ambiguous")
    defer { ambiguous.shutdown() }
    ambiguous.mergeDiscovered(DiscoveryResult(agents: [observed]))
    ambiguous.mergeHerdr([try live(), try live(pane: "w1:p2", terminal: "term-2")], session: "fixture")
    check(ambiguous.activeAgents.count == 3 && ambiguous.agent(for: observed.id)?.isObserved == true, "two live owners never choose an arbitrary transcript reply destination")
    ambiguous.mergeDiscovered(DiscoveryResult(agents: [newer]))
    check(ambiguous.snapshot.agents.filter { $0.isHerdr && $0.sourcePath != nil }.isEmpty, "ambiguous discovery refresh leaves both terminal identities separate")
    let split = makeStore("herdr-becomes-ambiguous")
    defer { split.shutdown() }
    split.mergeDiscovered(DiscoveryResult(agents: [observed]))
    split.mergeHerdr([try live()], session: "fixture")
    split.mergeHerdr([try live(), try live(pane: "w1:p2", terminal: "term-2")], session: "fixture")
    split.mergeDiscovered(DiscoveryResult(agents: [observed]))
    check(split.agent(for: observed.id)?.isObserved == true && split.agent(for: observed.id)?.canReceive == false, "new ambiguity removes prior alias from history card and existing popout")

    let conflicts = makeStore("herdr-draft-conflict")
    defer { conflicts.shutdown() }
    conflicts.mergeHerdr([try live()], session: "fixture")
    let liveID = conflicts.activeAgents[0].id
    conflicts.setDraft("Live draft", for: "agent:" + liveID)
    conflicts.snapshot.agents.append(observed)
    conflicts.setDraft("History draft", for: "agent:" + observed.id)
    conflicts.mergeHerdr([try live()], session: "fixture")
    check(conflicts.activeAgents.count == 2 && conflicts.draft(for: "agent:" + liveID) == "Live draft" && conflicts.draft(for: "agent:" + observed.id) == "History draft", "conflicting drafts keep both cards without losing either composition")
    conflicts.setDraft("", for: "agent:" + liveID)
    conflicts.mergeHerdr([try live()], session: "fixture")
    check(conflicts.activeAgents.count == 1 && conflicts.draft(for: "agent:" + liveID) == "History draft", "resolving draft conflict permits exact conversation join")
    check(try live(kind: "path").nativeSessionID == nil, "path-valued Herdr session cannot match transcript ID")
    check(try live(sessionProvider: "claude").nativeSessionID == nil, "mismatched native provider cannot link to live agent")
    check(try live("  ").nativeSessionID == nil, "blank native identity cannot join conversations")
    let different = makeStore("herdr-provider-mismatch")
    defer { different.shutdown() }
    different.mergeDiscovered(DiscoveryResult(agents: [observed]))
    different.mergeHerdr([try live(provider: "claude")], session: "fixture")
    check(different.activeAgents.count == 2, "same native ID from different providers stays separate")
}
