import Foundation
import OneCore
import Darwin

@main struct NativeTests {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else { fatalError("FAIL: \(name)") }
            count += 1
            print("PASS: \(name)")
        }
        runMarkdownTests { condition, name in check(condition, name) }
        var tap = ModifierDoubleTap()
        check(!tap.update(pressed: true, otherModifiers: false, at: 1), "single Control press does not trigger Talk")
        check(!tap.update(pressed: false, otherModifiers: false, at: 1.05), "single Control release does not trigger Talk")
        _ = tap.update(pressed: true, otherModifiers: false, at: 1.15)
        check(tap.update(pressed: false, otherModifiers: false, at: 1.20), "double Control triggers on the second short release")
        _ = tap.update(pressed: true, otherModifiers: false, at: 2)
        _ = tap.update(pressed: false, otherModifiers: false, at: 2.05)
        tap.cancel() // key press or mouse click between taps
        _ = tap.update(pressed: true, otherModifiers: false, at: 2.1)
        check(!tap.update(pressed: false, otherModifiers: false, at: 2.15), "typing or clicking between taps cancels the shortcut")
        _ = tap.update(pressed: true, otherModifiers: true, at: 2.2)
        check(!tap.update(pressed: false, otherModifiers: false, at: 2.25), "Control chords do not become a modifier tap")
        _ = tap.update(pressed: true, otherModifiers: false, at: 3)
        _ = tap.update(pressed: false, otherModifiers: false, at: 3.8)
        _ = tap.update(pressed: true, otherModifiers: false, at: 3.9)
        check(!tap.update(pressed: false, otherModifiers: false, at: 3.95), "holding Control does not count as a tap")
        _ = tap.update(pressed: true, otherModifiers: false, at: 5)
        check(!tap.update(pressed: false, otherModifiers: false, at: 5.05), "slow separate taps do not trigger Talk")
        tap.cancel()
        _ = tap.update(pressed: false, otherModifiers: true, at: 6)
        check(!tap.update(pressed: false, otherModifiers: true, at: 6.1), "Option and other modifiers cannot trigger Control shortcut")
        check(CardNavigation.visibleRange(count: 0, selection: 0).isEmpty, "empty Inbox has no page dots")
        check(CardNavigation.visibleRange(count: 40, selection: 0) == 0..<7, "large Inbox rail is capped at seven dots")
        check(CardNavigation.visibleRange(count: 40, selection: 20) == 17..<24, "rail follows selected middle card")
        check(CardNavigation.visibleRange(count: 40, selection: 39) == 33..<40, "last card remains visible in bounded rail")
        check(CardNavigation.visibleRange(count: 3, selection: 2) == 0..<3, "small Inbox shows each card once")
        let location = ProjectLocation(directory: "/Users/test/orca/workspaces/the-open-one/zoanthid")
        check(location.projectName == "the-open-one" && location.worktreeName == "zoanthid", "group Orca worktree under its project")
        check(ProjectLocation(directory: "/code/app/.worktrees/fix").projectPath == "/code/app", "group local worktree under project root")
        check(ProjectLocation(directory: "/code/app").worktreeName == nil, "ordinary directory is not labeled as a worktree")
        let leftDisplay = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let rightDock = WindowPlacement.docked(CGRect(x: -100, y: 700, width: 63, height: 360), to: leftDisplay)
        check(rightDock.maxX == 0 && rightDock.maxY == 900, "dock to right edge on a negative-origin display")
        let leftDock = WindowPlacement.docked(CGRect(x: 1000, y: 300, width: 63, height: 360), to: CGRect(x: 0, y: 0, width: 1710, height: 1000), right: false)
        check(leftDock.minX == 0 && leftDock.minY == 300, "explicit left docking preserves vertical position")
        check(WindowPlacement.docked(CGRect(x: 1500, y: 300, width: 63, height: 360), to: CGRect(x: 0, y: 0, width: 1710, height: 1000)).maxX == 1710, "drag near right edge snaps toolbar right")
        var clickGesture = ToolbarGesture(start: CGPoint(x: 10, y: 10))
        clickGesture.update(CGPoint(x: 12, y: 11))
        check(clickGesture.shouldClick(releasedInside: true), "toolbar tolerates small click movement")
        check(!clickGesture.shouldClick(releasedInside: false), "release outside control does not activate it")
        var dragGesture = ToolbarGesture(start: CGPoint(x: 10, y: 10))
        check(dragGesture.update(CGPoint(x: 15, y: 10)), "toolbar drag starts without a hold delay")
        dragGesture.update(CGPoint(x: 10, y: 10))
        check(!dragGesture.shouldClick(releasedInside: true), "dragging back to origin never triggers a button action")
        let dots = ToolbarStatus.summaries(for: [
            Agent(id: "a", name: "a", provider: "Claude", state: .done),
            Agent(id: "b", name: "b", provider: "Claude Code", state: .working),
            Agent(id: "c", name: "c", provider: "Codex", state: .idle),
            Agent(id: "d", name: "d", provider: "Codex", state: .waiting),
            Agent(id: "e", name: "e", provider: "Other", state: .working, archived: true)
        ])
        check(dots.count == 2 && dots.map(\.provider) == ["Codex", "Claude"], "toolbar groups providers and places attention before activity")
        check(dots[1].count == 2 && dots[1].state == .working, "Claude aliases share one working indicator")
        check(dots[0].state == .waiting, "provider indicator prioritizes an unanswered question")
        check(ToolbarStatus.summaries(for: [Agent(id: "busy", name: "busy", provider: "Codex", state: .working), Agent(id: "idle", name: "idle", provider: "Claude", state: .idle)]).map(\.provider) == ["Codex", "Claude"], "active indicator precedes idle provider regardless of provider name")
        check(ToolbarStatus.summaries(for: [Agent(id: "x", name: "x", provider: "Codex", state: .done)]).first?.state == .idle, "finished history does not appear as live activity")
        let running = [
            Agent(id: "codex-a", name: "a", provider: "Codex", state: .working),
            Agent(id: "codex-b", name: "b", provider: "Codex", state: .working),
            Agent(id: "claude", name: "c", provider: "Claude", state: .working),
            Agent(id: "waiting", name: "w", provider: "Codex", state: .waiting),
            Agent(id: "done", name: "d", provider: "Codex", state: .done),
            Agent(id: "idle", name: "i", provider: "Claude", state: .idle),
            Agent(id: "unknown", name: "u", provider: "Codex", state: .unknown),
            Agent(id: "archived", name: "x", provider: "Codex", state: .working, archived: true)
        ]
        let runningDots = ToolbarStatus.runningIndicators(for: running)
        check(runningDots.count == 3, "toolbar shows one dot per running conversation, including same-provider agents")
        check(Set(runningDots.map(\.id)) == ["codex-a", "codex-b", "claude"], "waiting, finished, idle, unknown and archived chats add no running dots")
        check(runningDots.allSatisfy { $0.state == .working }, "running stack never contains a red Inbox attention marker")
        check(ToolbarStatus.runningIndicators(for: []).isEmpty, "empty running stack does not invent an idle agent dot")
        check(ToolbarStatus.runningIndicators(for: Array(running.reversed())) == runningDots, "dot identities and order survive conversation reordering")
        var finished = running; finished[0].state = .done
        check(ToolbarStatus.runningIndicators(for: finished).count == 2, "finishing a turn removes exactly that running dot")
        let clock = Date()
        var tracker = ToolbarActivity()
        tracker.update(running, now: clock)
        let activity = ToolbarStatus.activityIndicators(for: running, reviewed: [:], completedUntil: tracker.completedUntil, now: clock)
        check(activity.count == 4 && !activity.contains { $0.id == "done" }, "old unreviewed results never add toolbar dots")
        tracker.update(finished, now: clock)
        let completed = ToolbarStatus.activityIndicators(for: finished, reviewed: [:], completedUntil: tracker.completedUntil, now: clock)
        check(completed.map(\.id) == activity.map(\.id) && completed.first { $0.id == "codex-a" }?.state == .done, "finishing changes the existing working dot to green without adding one")
        check(ToolbarStatus.activityLabel(for: completed) == "2 working · 1 need an answer · 1 just finished", "status label separates active work from brief completion signals")
        tracker.update(finished, now: clock.addingTimeInterval(19))
        check(tracker.completedUntil["codex-a"] == clock.addingTimeInterval(20), "refreshing an old completion cannot extend its pulse")
        tracker.update(finished, now: clock.addingTimeInterval(20))
        check(tracker.completedUntil.isEmpty && ToolbarStatus.activityIndicators(for: finished, reviewed: [:], completedUntil: tracker.completedUntil, now: clock.addingTimeInterval(20)).count == 3, "completion dot expires after twenty seconds without requiring review")
        var restarted = ToolbarActivity(); restarted.update(finished, now: clock)
        check(restarted.completedUntil.isEmpty, "restart does not replay historical green dots")
        tracker.update(running, now: clock); tracker.update(finished, now: clock)
        let reviewed = ToolbarStatus.activityIndicators(for: finished, reviewed: ["codex-a": finished[0].updatedAt], completedUntil: tracker.completedUntil, now: clock)
        check(!reviewed.contains { $0.id == "codex-a" }, "review can dismiss the brief completion signal early")
        tracker.update(running, now: clock)
        check(tracker.completedUntil.isEmpty, "starting work again replaces green immediately")
        tracker.update(finished, now: clock); tracker.update([], now: clock)
        check(tracker.completedUntil.isEmpty, "untracking removes pending completion signals")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("open-one-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try BridgePaths.prepare(root)
        try runProjectTests(root: root) { condition, name in check(condition, name) }
        try runTrackingTests(root: root) { condition, name in check(condition, name) }
        runInboxTests(root: root) { condition, name in check(condition, name) }
        var state = Snapshot()
        let event = AgentEvent(id: "one", agentID: "test", kind: "question", text: "Which layout?", choices: ["First", "Second"], requestID: "q1")
        check(state.apply(event), "accept question")
        check(!state.apply(event), "deduplicate replay")
        check(state.agents[0].state == .waiting, "question waits")
        check(!state.apply(AgentEvent(agentID: "bad", kind: "question", text: "Missing request")), "reject invalid event")
        let saved = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(state))
        check(saved.agents == state.agents, "persist conversation")
        check(BridgePaths.safeFilename("../../x").contains("/") == false, "contain reply paths")
        try JSONEncoder().encode(event).write(to: root.appendingPathComponent("events/001.json"))
        let store = Store(root: root, demo: false)
        store.pollEvents()
        check(store.selected?.id == "test", "poll selects incoming agent")
        check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("events/001.json").path), "acknowledge persisted event")
        store.stage("First", choice: 0)
        check(store.pending != nil, "reply enters undo window")
        let replyPath = root.appendingPathComponent("replies/\(BridgePaths.safeFilename("q1")).json")
        check(!FileManager.default.fileExists(atPath: replyPath.path), "no delivery before undo window")
        store.undo()
        try await Task.sleep(nanoseconds: 2_100_000_000)
        check(!FileManager.default.fileExists(atPath: replyPath.path), "undo prevents delivery")
        check(store.selected?.state == .waiting, "undo leaves question open")
        store.stage("Second", choice: 1)
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: replyPath.path) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        check(FileManager.default.fileExists(atPath: replyPath.path), "reply delivered within deadline")
        let reply = try JSONDecoder().decode(AgentReply.self, from: Data(contentsOf: replyPath))
        check(reply.text == "Second" && reply.choiceIndex == 1, "deliver exact selected reply")
        check(store.selected?.state == .working, "reply advances agent state")
        check(store.selected?.requestID == nil, "close answered request")
        // A newer question invalidates a reply waiting in the two-second window.
        store.snapshot.apply(AgentEvent(agentID: "test", kind: "question", text: "Old?", requestID: "old"))
        store.stage("Yes")
        store.snapshot.apply(AgentEvent(agentID: "test", kind: "question", text: "New?", requestID: "new"))
        for _ in 0..<100 {
            if store.pending == nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        check(store.pending == nil, "stale reply is resolved")
        check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("replies/\(BridgePaths.safeFilename("old")).json").path), "reject stale staged answer")
        check(store.selected?.requestID == "new", "preserve replacement question")
        store.archiveSelected()
        check(store.selected?.archived == false, "cannot clear a waiting agent")
        try Data("not json".utf8).write(to: root.appendingPathComponent("events/invalid.json"))
        store.pollEvents()
        let rejected = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("rejected").path)
        check(rejected.count == 1, "quarantine malformed event")
        var parsed: [String] = []
        AgentRunner.parse(Data(#"{"type":"thread.started","thread_id":"thread-1"}"#.utf8)) { update in
            if case .session(let id) = update { parsed.append(id) }
        }
        AgentRunner.parse(Data(#"{"type":"item.completed","item":{"type":"agent_message","text":"Real output"}}"#.utf8)) { update in
            if case .text(let text) = update { parsed.append(text) }
        }
        check(parsed == ["thread-1", "Real output"], "parse Codex stream")
        var claudeText = ""
        AgentRunner.parse(Data(#"{"type":"assistant","message":{"content":[{"type":"text","text":"Claude output"}]}}"#.utf8)) { update in
            if case .text(let text) = update { claudeText = text }
        }
        check(claudeText == "Claude output", "parse Claude stream")
        let fakeCLI = root.appendingPathComponent("fake-codex")
        try """
        #!/bin/sh
        printf '%s\\n' '{"type":"thread.started","thread_id":"fake-thread"}' '{"type":"item.completed","item":{"type":"agent_message","text":"Mock process completed"}}'
        """.write(to: fakeCLI, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeCLI.path)
        let runner = AgentRunner(executableOverride: fakeCLI)
        let received: [String] = await withCheckedContinuation { continuation in
            let collector = TestCollector()
            runner.start(agent: Agent(id: "mock", name: "mock", provider: "Codex", directory: root.path, managed: true), prompt: "Test", image: nil) { update in
                switch update {
                case .session(let id): collector.items.append(id)
                case .text(let text): collector.items.append(text)
                case .finished(let code): collector.items.append("exit:\(code)"); continuation.resume(returning: collector.items)
                case .error(let error): continuation.resume(returning: [error])
                default: break
                }
            }
        }
        check(received == ["fake-thread", "Mock process completed", "exit:0"], "managed subprocess streams and completes")
        store.snapshot.apply(AgentEvent(agentID: "second", kind: "question", text: "Second agent?", requestID: "second-request"))
        store.selection = "test"
        store.stage("Answer second", agentID: "second")
        check(store.pending?.agentID == "second", "floating panel addresses its own agent")
        store.undo()
        store.stage("Do not misroute", agentID: "missing")
        check(store.pending == nil, "missing floating recipient cannot fall back to selected agent")
        store.shutdown()
        try await runDiscoveryTests(root: root) { condition, name in check(condition, name) }
        try await runLiveTranscriptTests(root: root) { condition, name in check(condition, name) }
        try runMultiHomeDiscoveryTests(root: root) { condition, name in check(condition, name) }
        try await runScreenshotTests(root: root) { condition, name in check(condition, name) }
        try await runProcessTests(root: root) { condition, name in check(condition, name) }
        try await runApprovalTests(root: root) { condition, name in check(condition, name) }
        try await runResumeTests(root: root) { condition, name in check(condition, name) }
        try await runCodexQueueTests(root: root) { condition, name in check(condition, name) }
        try await runWriterConflictTests(root: root) { condition, name in check(condition, name) }
        try await runResumeFailureTests(root: root) { condition, name in check(condition, name) }
        try await runProviderTests(root: root) { condition, name in check(condition, name) }
        try runStoreRegressionTests(root: root) { condition, name in check(condition, name) }
        try runPhoneDeliveryTests(root: root) { condition, name in check(condition, name) }
        try await runHerdrTests(root: root) { condition, name in check(condition, name) }
        try await runStoreHerdrTests(root: root) { condition, name in check(condition, name) }
        try runUtilityTests(root: root) { condition, name in check(condition, name) }
        print("\(count) native checks passed")
    }
}

private final class TestCollector { var items: [String] = [] }
