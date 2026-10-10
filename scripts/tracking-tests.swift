import Foundation
import OneCore

@MainActor func runTrackingTests(root: URL, check: (Bool, String) -> Void) throws {
    let folder = root.appendingPathComponent("tracking-tests")
    let store = Store(root: folder)
    defer { store.shutdown() }
    let main = root.appendingPathComponent("projects/repo").resolvingSymlinksInPath().path
    let linked = root.appendingPathComponent("projects/outside/fix checkout").resolvingSymlinksInPath().path
    let other = root.appendingPathComponent("projects/outside/second").resolvingSymlinksInPath().path
    store.snapshot.agents = [
        Agent(id: "main", name: "main", directory: main, state: .done),
        Agent(id: "linked", name: "linked", directory: linked + "/src/deep", state: .waiting, requestID: "tracked-question"),
        Agent(id: "other", name: "other", directory: other, state: .working)
    ]
    store.selection = "linked"; store.draft = "Unsent answer"
    check(store.runningToolbarIndicators.map(\.id) == ["other"], "toolbar counts running chats separately from waiting and completed Inbox items")
    store.notice = "Informational notice"
    check(store.runningToolbarIndicators.count == 1 && store.inboxNeedsAttention, "a notice changes Inbox attention without adding an agent dot")
    store.notice = nil
    store.stage(store.draft)
    store.trackWorktree(linked, enabled: false)
    check(store.activeAgents.map(\.id).sorted() == ["main", "other"], "removing checkout excludes nested sessions without excluding sibling or main checkout")
    check(store.pending == nil && store.draft(for: "agent:linked") == "Unsent answer", "removing worktree cancels staged reply and preserves its draft")
    check(store.selection != "linked" && store.snapshot.agents.count == 3, "tracking removal changes selection without deleting history")
    store.snapshot.agents.append(Agent(id: "future", name: "future", directory: "/unselected/new-worktree", state: .done))
    check(!store.activeAgents.contains { $0.id == "future" }, "manual worktree selection excludes newly discovered worktrees")
    store.trackOnlyWorktree(linked + "/src/deep")
    check(store.activeAgents.map(\.id) == ["linked"] && store.trackedWorktreePaths == [linked], "Only this resolves nested cwd to exact checkout")
    store.trackConversation("linked", enabled: false)
    check(store.activeAgents.isEmpty && !store.inboxNeedsAttention && store.routingCandidates.isEmpty, "removed conversation disappears from Inbox, routing and toolbar attention")
    store.snapshot.apply(AgentEvent(agentID: "linked", kind: "done", text: "Finished after removal"))
    check(store.activeAgents.isEmpty && store.removedConversations.count == 1, "new completion cannot restore an explicitly removed conversation")
    store.stage("Should not send", agentID: "linked")
    check(store.pending == nil, "removed popout cannot send to hidden conversation")
    store.notice = nil
    store.trackConversation("linked", enabled: true)
    check(store.activeAgents.map(\.id) == ["linked"] && store.inboxNeedsAttention, "Add back restores conversation and completion indicator")
    store.trackWorktree(other, enabled: true)
    store.trackConversation("other", enabled: false)
    check(store.runningToolbarIndicators.isEmpty, "removed running conversations contribute no sidebar dot")
    check(store.snapshot.agents.first { $0.id == "other" }?.state == .working, "removing running conversation never stops its process or changes its state")
    store.save(); store.shutdown()
    let restored = Store(root: folder)
    defer { restored.shutdown() }
    check(restored.trackedWorktreePaths == [linked, other] && restored.ignoredConversationIDs == ["other"], "worktree and conversation selections survive restart")
    check(restored.activeAgents.map(\.id) == ["linked"] && restored.draft(for: "agent:linked") == "Unsent answer", "restart preserves filtered Inbox and hidden drafts")
    restored.removeAllTrackedWorktrees()
    check(restored.activeAgents.isEmpty && restored.trackedWorktreePaths?.isEmpty == true, "Remove all is an explicit empty selection")
    restored.setTrackAllWorktrees(true)
    check(restored.activeAgents.count == 3 && !restored.activeAgents.contains { $0.id == "other" }, "automatic tracking does not undo individual conversation removals")

    let history = folder.appendingPathComponent("transcripts")
    try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
    let now = Date()
    for index in 0..<45 {
        let file = history.appendingPathComponent("\(index).jsonl")
        let record: [String: Any] = ["type": "session_meta", "payload": ["id": "scan-\(index)", "cwd": index == 44 ? linked + "/src/deep" : other]]
        try JSONSerialization.data(withJSONObject: record).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-Double(index))], ofItemAtPath: file.path)
    }
    let scanner = SessionDiscovery(codexRoot: history, claudeRoot: folder.appendingPathComponent("empty"))
    let result = scanner.scan(now: now, trackedWorktreePaths: [linked])
    check(result.agents.map(\.sessionID) == ["scan-44"], "untracked recent transcripts do not consume selected worktree's forty-session quota")
    check(scanner.scan(now: now, trackedWorktreePaths: [linked]).agents == result.agents, "cached discovery honors worktree selection")
    check(scanner.scan(now: now, trackedWorktreePaths: []).agents.isEmpty, "empty tracking selection skips transcript discovery")
    restored.trackOnlyWorktree(linked)
    var notifications = 0
    restored.onAttention = { notifications += 1 }
    let event = AgentEvent(agentID: "main", kind: "done", text: "Untracked completion")
    try JSONEncoder().encode(event).write(to: folder.appendingPathComponent("events/hidden.json"))
    restored.pollEvents()
    check(notifications == 0 && !restored.activeAgents.contains { $0.id == "main" }, "untracked bridge events update stored history without raising attention")
    let terminals = folder.appendingPathComponent("new-terminals")
    try FileManager.default.createDirectory(at: terminals, withIntermediateDirectories: true)
    let liveScanner = SessionDiscovery(codexRoot: terminals, claudeRoot: folder.appendingPathComponent("no-claude"))
    let freshStore = Store(root: folder.appendingPathComponent("fresh-store"))
    defer { freshStore.shutdown() }
    freshStore.trackOnlyWorktree(linked)
    freshStore.snapshot.agents = [Agent(id: "busy", name: "Existing work", directory: linked, state: .working)]
    freshStore.mergeDiscovered(liveScanner.scan())
    let transcript = terminals.appendingPathComponent("new.jsonl")
    let metadata: [String: Any] = ["type": "session_meta", "payload": ["id": "new-terminal", "cwd": linked + "/src"]]
    let complete: [String: Any] = ["type": "event_msg", "payload": ["type": "task_complete", "last_agent_message": "Hello"]]
    var transcriptData = try JSONSerialization.data(withJSONObject: metadata)
    transcriptData.append(10); transcriptData.append(try JSONSerialization.data(withJSONObject: complete))
    try transcriptData.write(to: transcript)
    freshStore.mergeDiscovered(liveScanner.scan(trackedWorktreePaths: freshStore.trackedWorktreePaths))
    let newID = "observed:codex:new-terminal"
    check(freshStore.activeAgents.contains { $0.id == newID }, "next scan automatically discovers a newly opened conversation in a selected checkout")
    check(AgentDirectoryProject.groups(for: freshStore.activeAgents).flatMap(\.focusSections).flatMap(\.agents).contains { $0.id == newID }, "new completed terminal appears in expanded project beside an existing running agent")
    check(freshStore.inboxAgents.contains { $0.id == newID }, "new terminal completion appears in Inbox as well as Agents")
    freshStore.trackConversation(newID, enabled: false)
    freshStore.mergeDiscovered(liveScanner.scan(trackedWorktreePaths: freshStore.trackedWorktreePaths))
    check(!freshStore.activeAgents.contains { $0.id == newID }, "discovery refresh preserves explicit terminal removal")

}
