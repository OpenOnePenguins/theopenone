import Foundation
import OneCore

@MainActor func runProjectTests(root: URL, check: (Bool, String) -> Void) throws {
    let fm = FileManager.default
    let base = root.appendingPathComponent("projects").resolvingSymlinksInPath()
    let main = base.appendingPathComponent("repo")
    let worktree = base.appendingPathComponent("outside/fix checkout")
    let other = base.appendingPathComponent("outside/second")
    let admin = main.appendingPathComponent(".git/worktrees/internal-id")
    for path in [main.appendingPathComponent("src"), admin, worktree.appendingPathComponent("src/deep"), other] {
        try fm.createDirectory(at: path, withIntermediateDirectories: true)
    }
    try "../..\n".write(to: admin.appendingPathComponent("commondir"), atomically: true, encoding: .utf8)
    try "gitdir: ../../repo/.git/worktrees/internal-id\n".write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
    try "gitdir: \(admin.path)\n".write(to: other.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
    let nested = ProjectLocation(directory: worktree.appendingPathComponent("src/deep").path)
    check(nested.projectPath == main.path && nested.worktreeName == "fix checkout" && nested.worktreePath == worktree.path, "resolve arbitrary linked worktree and nested cwd using relative Git metadata")
    check(ProjectLocation(directory: other.path).projectPath == main.path, "absolute Git pointer joins sibling worktree to same project")
    let normal = ProjectLocation(directory: main.appendingPathComponent("src").path)
    check(normal.projectPath == main.path && normal.worktreeName == nil, "main checkout subdirectories share project without a worktree label")
    let alias = base.appendingPathComponent("alias")
    try fm.createSymbolicLink(at: alias, withDestinationURL: worktree)
    check(ProjectLocation(directory: alias.appendingPathComponent("src").path) == nested, "symlinked worktree path resolves to the same group")
    let submodule = main.appendingPathComponent("module")
    try fm.createDirectory(at: submodule, withIntermediateDirectories: true)
    try "gitdir: ../.git/modules/module\n".write(to: submodule.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
    let sub = ProjectLocation(directory: submodule.path)
    check(sub.projectPath == submodule.path && sub.worktreeName == nil, "submodule Git pointer is not mistaken for a linked worktree")
    let historical = ProjectLocation(directory: "/missing/orca/workspaces/token-abacus/barramundi/motion")
    check(historical.projectName == "token-abacus" && historical.worktreeName == "barramundi", "historical Orca subdirectory retains its worktree label")
    check(ProjectLocation(directory: "/missing/workspaces/normal/source").worktreeName == nil, "generic workspace folder is not assumed to be Orca")
    check(ProjectLocation(directory: "/missing/app/.worktrees/fix/src").worktreeName == "fix", "historical local worktree subdirectory retains its label")

    let date = Date()
    let rows = [
        Agent(id: "done", name: "done", directory: main.path, state: .done, updatedAt: date),
        Agent(id: "working", name: "working", directory: worktree.path, state: .working, updatedAt: date.addingTimeInterval(-10)),
        Agent(id: "waiting", name: "waiting", directory: worktree.appendingPathComponent("src").path, state: .waiting, updatedAt: date.addingTimeInterval(-100)),
        Agent(id: "other", name: "other", directory: other.path, state: .idle, updatedAt: date.addingTimeInterval(-86401)),
        Agent(id: "recent", name: "recent", directory: base.appendingPathComponent("alphabetically-first").path, state: .idle, updatedAt: date.addingTimeInterval(10))
    ]
    let groups = AgentDirectoryProject.groups(for: rows, now: date)
    check(groups.count == 2 && groups[0].id == main.path, "project with waiting agent precedes a more recent inactive project")
    check(groups[0].sections.count == 3 && groups[0].sections[0].worktreeName == "fix checkout", "main checkout and linked worktrees have separate sections")
    check(groups[0].sections[0].agents.map(\.id) == ["waiting", "working"], "nested worktree chats share one section ordered by attention then activity")
    check(groups[0].focusSections.flatMap(\.agents).map(\.id) == ["waiting", "working", "done"] && groups[0].otherCount == 1, "recent completed conversation stays visible alongside running work")
    check(groups[0].otherSections.flatMap(\.agents).map(\.id) == ["other"], "only older inactive history collapses within a busy project")
    let freshReady = Agent(id: "new-terminal", name: "New terminal", directory: worktree.path, state: .unknown, updatedAt: date)
    let withReady = AgentDirectoryProject.groups(for: rows + [freshReady], now: date)
    check(withReady[0].focusSections.flatMap(\.agents).contains { $0.id == freshReady.id }, "newly discovered terminal remains visible before a final response")
    let aged = AgentDirectoryProject.groups(for: rows + [freshReady], now: date.addingTimeInterval(86401))
    check(aged[0].focusSections.flatMap(\.agents).map(\.id) == ["waiting", "working"], "older history collapses without hiding ongoing work")
    check(groups[1].focusSections.flatMap(\.agents).map(\.id) == ["recent"] && groups[1].otherCount == 0, "inactive project keeps its recent conversation visible")
    check(rows.sorted(by: AgentConversationOrder.precedes).map(\.id) == ["waiting", "working", "recent", "done", "other"], "conversation ordering is waiting, working, then recency")
    let tied = [Agent(id: "z", name: "z", updatedAt: date), Agent(id: "a", name: "a", updatedAt: date)]
    check(tied.sorted(by: AgentConversationOrder.precedes).map(\.id) == ["a", "z"], "equal timestamps have a stable tie-breaker")
    let store = Store(root: root.appendingPathComponent("ordering-store"))
    store.snapshot.agents = rows
    store.selection = "working"
    check(store.visible.map(\.id) == ["waiting", "working", "recent", "done", "other"], "Inbox and directory use the same conversation order")
    store.snapshot.agents[0].state = .waiting
    check(store.visible.first?.id == "done" && store.selected?.id == "working", "new attention reorders list without switching the selected conversation")
    store.shutdown()
}
