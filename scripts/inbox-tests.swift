import Foundation
import OneCore

@MainActor func runInboxTests(root: URL, check: (Bool, String) -> Void) {
    let now = Date()
    let agents = [
        Agent(id: "idle", name: "idle", state: .idle),
        Agent(id: "running", name: "running", state: .working, updatedAt: now),
        Agent(id: "done-old", name: "done-old", state: .done, updatedAt: now.addingTimeInterval(-20)),
        Agent(id: "done", name: "done", state: .done, updatedAt: now),
        Agent(id: "waiting", name: "waiting", state: .waiting, choices: ["Yes", "No"], requestID: "question"),
        Agent(id: "offline", name: "offline", state: .offline),
        Agent(id: "history", name: "history", state: .unknown),
        Agent(id: "archived", name: "archived", state: .done, archived: true)
    ]
    let sections = InboxSection.groups(for: agents)
    check(sections.map(\.title) == ["Needs you", "Finished", "Running", "Idle", "Offline", "History"], "Inbox separates replies, results and running work in priority order")
    check(sections.flatMap(\.agents).map(\.id) == ["waiting", "done", "done-old", "running", "idle", "offline", "history"], "All view includes inactive history, excludes archived chats and sorts results by recency")
    let store = Store(root: root.appendingPathComponent("inbox-list-tests"))
    defer { store.shutdown() }
    store.snapshot.agents = agents
    store.inboxScope = .all
    store.selection = "waiting"
    store.moveSelection(1)
    check(store.selected?.id == "done", "Inbox keyboard navigation follows section order instead of all-chat order")
    store.moveSelection(1); store.moveSelection(1)
    check(store.selected?.id == "running", "Inbox keyboard navigation reaches running group after results")
    store.selection = "missing"; store.moveSelection(1)
    check(store.selected?.id == "waiting", "navigation from an idle detail starts at first actionable row")
    store.selection = "waiting"; store.draft = "Keep selected draft"
    store.archiveAgent("done")
    check(store.selected?.id == "waiting" && store.draft == "Keep selected draft" && !store.inboxAgents.contains { $0.id == "done" }, "dismissing another result never steals selection or its draft")
    store.archiveAgent("waiting")
    check(store.inboxAgents.contains { $0.id == "waiting" }, "unanswered questions cannot be dismissed as finished work")
    store.notice = "Connection notice"
    store.selection = "done-old"; store.archiveSelected()
    check(store.selected?.id == "waiting" && store.notice == "Connection notice", "clearing selected result advances to actionable row without treating notices as chats")
    store.stage("No", choice: 1, agentID: "waiting")
    store.selection = "running"
    check(store.pending?.agentID == "waiting" && store.pending?.choiceIndex == 1, "inline answer captures its own row independently of open conversation")
    store.undo()
    store.search = "waiting"
    check(store.inboxAgents.map(\.id) == ["waiting"], "Inbox search filters action sections")
    store.search = ""; store.trackConversation("waiting", enabled: false)
    check(store.inboxAgents.map(\.id) == ["running", "idle", "offline", "history"], "Inbox sections respect persistent conversation tracking")
    store.snapshot.agents = agents
    store.trackConversation("waiting", enabled: true)
    store.setInboxScope(.review)
    check(store.inboxAgents.map(\.id) == ["waiting", "done", "done-old"], "default review scope excludes running agents and inactive history")
    store.selection = "done"; store.draft = "Keep my follow-up"
    store.markReviewed(["done", "waiting", "running"])
    check(store.inboxAgents.map(\.id) == ["waiting", "done-old"] && store.activeAgents.contains { $0.id == "done" }, "reviewing a result removes only finished attention, without archiving or hiding questions")
    check(store.draft(for: "agent:done") == "Keep my follow-up", "reviewing preserves the conversation draft")
    store.setInboxScope(.all)
    check(store.inboxAgents.contains { $0.id == "done" }, "reviewed result remains available in All")
    store.setInboxScope(.running)
    check(store.inboxAgents.map(\.id) == ["running"] && store.selection == "running", "running scope selects only a running conversation")
    store.setInboxScope(.review)
    store.snapshot.agents[3].updatedAt = now.addingTimeInterval(5)
    check(store.inboxAgents.contains { $0.id == "done" }, "new activity resurfaces a previously reviewed result")
    store.notice = nil
    store.markReviewed(["done", "done-old"])
    store.trackConversation("waiting", enabled: false)
    check(store.toolbarIndicators.map(\.id) == ["running"], "reviewed completions leave only running dots")
    check(!store.inboxNeedsAttention && store.inboxAgents.isEmpty, "reviewed results stop the Inbox attention badge")
    let restored = Store(root: root.appendingPathComponent("inbox-list-tests"))
    defer { restored.shutdown() }
    check(restored.reviewedResults["done"] == now.addingTimeInterval(5), "review receipts persist across restart")
    store.markNeedsReview("done")
    check(!store.toolbarIndicators.contains { $0.id == "done" }, "marking old history unreviewed never creates an active agent dot")
    check(store.inboxNeedsAttention && store.inboxAgents.map(\.id) == ["done"], "review action is reversible without archiving or changing agent activity")
    store.snapshot.agents[1].state = .done
    check(store.toolbarIndicators.first { $0.id == "running" }?.state == .done, "Store observes working-to-done changes immediately")
    store.refreshToolbarActivity(now: Date().addingTimeInterval(21))
    check(!store.toolbarIndicators.contains { $0.id == "running" }, "Store timer expires completion signals while the app is idle")
    check(store.activeAgents.contains { $0.id == "idle" }, "idle conversations remain available in Agents")
}
