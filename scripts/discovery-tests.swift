import Foundation
import CoreGraphics
import OneCore

@MainActor func runDiscoveryTests(root: URL, check: (Bool, String) -> Void) async throws {
    let now = Date()
    let stamp = ISO8601DateFormatter().string(from: now)
    let codex = """
    {"timestamp":"\(stamp)","type":"session_meta","payload":{"id":"external-codex","cwd":"/test/project","base_instructions":{"text":"PRIVATE SYSTEM PROMPT"}}}
    {"timestamp":"\(stamp)","type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"PRIVATE DEVELOPER PROMPT"}]}}
    {"timestamp":"\(stamp)","type":"event_msg","payload":{"type":"task_started"}}
    {"timestamp":"\(stamp)","type":"event_msg","payload":{"type":"user_message","message":"Build the pricing page"}}
    {"timestamp":"\(stamp)","type":"event_msg","payload":{"type":"agent_message","message":"Pricing is ready."}}
    {"timestamp":"\(stamp)","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Pricing is ready."}]}}
    {"timestamp":"\(stamp)","type":"event_msg","payload":{"type":"task_complete","last_agent_message":"Pricing is ready."}}
    """
    let codexAgent = try unwrap(SessionTranscript.parse(Data(codex.utf8), provider: "Codex", path: "/sample.jsonl", modified: now), "Codex transcript")
    check(codexAgent.state == .done && codexAgent.isObserved, "discover completed Codex session")
    check(codexAgent.messages.count == 2, "deduplicate transcript message representations")
    check(!codexAgent.messages.contains(where: { $0.text.contains("PRIVATE") }), "exclude system and developer prompts")
    check(codexAgent.title == "Build the pricing page", "derive title from actual user request")
    let working = codex.components(separatedBy: "\n").prefix(4).joined(separator: "\n")
    let stale = try unwrap(SessionTranscript.parse(Data(working.utf8), provider: "Codex", path: "/sample.jsonl", modified: now, now: now.addingTimeInterval(600)), "stale transcript")
    check(stale.state == .unknown, "old working transcript is not presented as live")
    let earlier = ISO8601DateFormatter().string(from: now.addingTimeInterval(-600))
    let modernHeader = """
    {"timestamp":"\(earlier)","type":"session_meta","payload":{"id":"modern-codex","cwd":"/test/live"}}
    """
    let workItem = """
    {"timestamp":"\(stamp)","type":"event_msg","payload":{"type":"item_completed","item":{"type":"CommandExecution","aggregated_output":"PRIVATE TOOL OUTPUT"}}}
    """
    let modern = modernHeader + "\n" + """
    {"timestamp":"\(earlier)","type":"event_msg","payload":{"type":"task_started"}}
    {"timestamp":"\(earlier)","type":"event_msg","payload":{"type":"item_completed","item":{"type":"UserMessage","id":"modern-user","content":[{"type":"text","text":"Fix live status"}]}}}
    {"timestamp":"\(earlier)","type":"event_msg","payload":{"type":"item_completed","item":{"type":"AgentMessage","id":"modern-agent","phase":"commentary","content":[{"type":"Text","text":"Checking activity."}]}}}
    {"timestamp":"\(stamp)","type":"event_msg","payload":{"type":"item_completed","item":{"type":"Reasoning","raw_content":"PRIVATE REASONING"}}}
    """ + "\n" + workItem
    let modernAgent = try unwrap(SessionTranscript.parse(Data(modern.utf8), provider: "Codex", path: "/modern.jsonl", modified: now, now: now), "modern transcript")
    check(modernAgent.state == .working, "recent work items keep a long Codex turn active")
    check(modernAgent.messages.map(\.text) == ["Fix live status", "Checking activity."], "modern transcript exposes only user-visible messages")
    check(modernAgent.title == "Fix live status", "modern user item supplies the session title")
    check(SessionTranscript.parse(Data(modern.utf8), provider: "Codex", path: "/modern.jsonl", modified: now, now: now.addingTimeInterval(600))?.state == .unknown, "modern activity still expires when stale")
    check(SessionTranscript.parse(Data((modernHeader + "\n" + workItem).utf8), provider: "Codex", path: "/tail.jsonl", modified: now, now: now)?.state == .working, "bounded tail recovers activity when task_started was omitted")
    let modernDone = modern + "\n" + """
    {"timestamp":"\(stamp)","type":"event_msg","payload":{"type":"item_completed","item":{"type":"AgentMessage","phase":"final","content":[{"type":"Text","text":"Fixed."}]}}}
    {"timestamp":"\(stamp)","type":"event_msg","payload":{"type":"token_count"}}
    """
    check(SessionTranscript.parse(Data(modernDone.utf8), provider: "Codex", path: "/done.jsonl", modified: now, now: now)?.state == .done, "final modern reply stays done after token bookkeeping")
    let forkedModern = modern.replacingOccurrences(of: "\"type\":\"item_completed\",", with: "\"type\":\"item_completed\",\"thread_id\":\"modern-fork\",")
    check(SessionTranscript.parse(Data(forkedModern.utf8), provider: "Codex", path: "/fork.jsonl", modified: now, now: now)?.sessionID == "modern-fork", "fork events override the copied parent session header")
    let claude = """
    {"timestamp":"\(stamp)","type":"user","sessionId":"external-claude","cwd":"/test/api","uuid":"u1","message":{"content":"Fix checkout"}}
    {"timestamp":"\(stamp)","type":"user","sessionId":"external-claude","cwd":"/test/api","uuid":"u2","message":{"content":[{"type":"tool_result","content":"SECRET TOOL OUTPUT"}]}}
    {"timestamp":"\(stamp)","type":"user","sessionId":"external-claude","cwd":"/test/api","uuid":"u3","message":{"content":"<task-notification>Background job metadata</task-notification>"}}
    {"timestamp":"\(stamp)","type":"assistant","sessionId":"external-claude","cwd":"/test/api","uuid":"a1","message":{"content":[{"type":"thinking","thinking":"PRIVATE REASONING"},{"type":"text","text":"Checkout is fixed."}],"stop_reason":"end_turn"}}
    """
    let claudeAgent = try unwrap(SessionTranscript.parse(Data(claude.utf8), provider: "Claude", path: "/claude.jsonl", modified: now), "Claude transcript")
    check(claudeAgent.state == .done && claudeAgent.messages.count == 2, "discover Claude turns without tool results or reasoning")
    let slashCommand = """
    {"timestamp":"\(stamp)","type":"user","sessionId":"external-claude","cwd":"/test/api","uuid":"command","message":{"content":"<command-name>/model</command-name>"}}
    """
    let filteredClaude = try unwrap(SessionTranscript.parse(Data((slashCommand + "\n" + claude).utf8), provider: "Claude", path: "/claude.jsonl", modified: now), "Claude command transcript")
    check(filteredClaude.title == "Fix checkout" && filteredClaude.messages.count == 2, "Claude local commands do not become chat titles or messages")
    let namedClaude = claude + "\n" + #"{"type":"ai-title","aiTitle":"Checkout investigation","sessionId":"external-claude"}"#
    check(SessionTranscript.parse(Data(namedClaude.utf8), provider: "Claude", path: "/claude.jsonl", modified: now)?.title == "Checkout investigation", "use Claude generated conversation title")
    let renamedClaude = namedClaude + "\n" + #"{"type":"custom-title","customTitle":"Checkout fix","sessionId":"external-claude"}"# + "\n" + #"{"type":"ai-title","aiTitle":"Another generated name","sessionId":"external-claude"}"#
    check(SessionTranscript.parse(Data(renamedClaude.utf8), provider: "Claude", path: "/claude.jsonl", modified: now)?.title == "Checkout fix", "explicit Claude chat rename takes precedence over generated titles")
    let scanRoot = root.appendingPathComponent("discovery")
    let codexRoot = scanRoot.appendingPathComponent("codex"), claudeRoot = scanRoot.appendingPathComponent("claude")
    try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
    let file = codexRoot.appendingPathComponent("rollout.jsonl")
    try codex.write(to: file, atomically: true, encoding: .utf8)
    try claude.write(to: claudeRoot.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: codexRoot.appendingPathComponent("link.jsonl"), withDestinationURL: file)
    let old = codexRoot.appendingPathComponent("old.jsonl")
    try codex.write(to: old, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-172800)], ofItemAtPath: old.path)
    let scanner = SessionDiscovery(codexRoot: codexRoot, claudeRoot: claudeRoot)
    let found = scanner.scan(now: now)
    check(found.agents.count == 2, "scan excludes symlinks and old sessions")
    check(scanner.scan(now: now).agents == found.agents, "unchanged discovery uses stable message identities")
    let titleIndex = scanRoot.appendingPathComponent("session_index.jsonl")
    try #"{"id":"external-codex","thread_name":"Named worktree conversation"}"#.write(to: titleIndex, atomically: true, encoding: .utf8)
    check(scanner.scan(now: now).agents.first(where: { $0.provider == "Codex" })?.title == "Named worktree conversation", "use Codex session name even when the transcript is cached")
    try #"{"id":"external-codex","thread_name":"Renamed worktree conversation"}"#.write(to: titleIndex, atomically: true, encoding: .utf8)
    check(scanner.scan(now: now).agents.first(where: { $0.provider == "Codex" })?.title == "Renamed worktree conversation", "refresh renamed chats independently of transcript activity")
    let duplicateRoot = scanRoot.appendingPathComponent("duplicates")
    try FileManager.default.createDirectory(at: duplicateRoot, withIntermediateDirectories: true)
    let currentCopy = duplicateRoot.appendingPathComponent("current.jsonl")
    let staleCopy = duplicateRoot.appendingPathComponent("old-copy.jsonl")
    try modern.write(to: currentCopy, atomically: true, encoding: .utf8)
    try modernDone.write(to: staleCopy, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: currentCopy.path)
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10)], ofItemAtPath: staleCopy.path)
    let duplicateScanner = SessionDiscovery(codexRoot: duplicateRoot, claudeRoot: scanRoot.appendingPathComponent("empty"))
    let latestOnly = duplicateScanner.scan(now: now).agents
    check(latestOnly.count == 1 && latestOnly.first?.sourcePath.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } == currentCopy.resolvingSymlinksInPath().path && latestOnly.first?.state == .working, "newest transcript wins over older completed copies of the same session")
    check(duplicateScanner.scan(now: now).agents == latestOnly, "cached discovery also keeps only the newest session copy")
    let storeRoot = root.appendingPathComponent("observed-store")
    let store = Store(root: storeRoot)
    store.mergeDiscovered(found)
    check(store.activeAgents.count == 2, "merge discovered sessions into Inbox")
    store.selection = codexAgent.id
    store.archiveSelected()
    store.mergeDiscovered(found)
    check(store.activeAgents.count == 1, "cleared observed session stays cleared until new activity")
    var newer = codexAgent; newer.updatedAt = now.addingTimeInterval(10)
    store.mergeDiscovered(DiscoveryResult(agents: [newer, claudeAgent]))
    check(store.activeAgents.count == 2, "new transcript activity restores cleared card")
    var olderCopy = codexAgent; olderCopy.state = .idle
    store.mergeDiscovered(DiscoveryResult(agents: [olderCopy]))
    check(store.snapshot.agents.first(where: { $0.id == codexAgent.id })?.updatedAt == newer.updatedAt, "older discovery cannot overwrite a newer stored session")
    store.snapshot.agents.append(Agent(id: "managed", name: "managed", provider: "Codex", sessionID: "external-codex", managed: true))
    store.mergeDiscovered(found)
    check(!store.snapshot.agents.contains(where: { $0.isObserved && $0.sessionID == "external-codex" }), "managed sessions are not duplicated by discovery")
    store.setDiscoveryEnabled(false)
    check(store.activeAgents.allSatisfy { !$0.isObserved }, "discovery toggle hides observed sessions")
    store.shutdown()

    let changedDirectory = codex + "\n" + #"{"type":"turn_context","payload":{"cwd":"/different/project"}}"#
    check(SessionTranscript.parse(Data(changedDirectory.utf8), provider: "Codex", path: "/sample.jsonl", modified: now)?.directory == "/different/project", "resumed Codex session uses its latest working directory")
    let recoveryRoot = root.appendingPathComponent("recovery-store")
    try BridgePaths.prepare(recoveryRoot)
    let damaged = Data("original unreadable state".utf8)
    try damaged.write(to: recoveryRoot.appendingPathComponent("state.json"))
    let recovered = Store(root: recoveryRoot, demo: false)
    recovered.save()
    let backups = try FileManager.default.contentsOfDirectory(at: recoveryRoot, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("state-recovery-") }
    check(backups.count == 1 && (try? Data(contentsOf: backups[0])) == damaged, "recover unreadable state without losing original bytes")
    recovered.shutdown()
    let replyStore = Store(root: root.appendingPathComponent("pending-store"), demo: false)
    replyStore.snapshot.apply(AgentEvent(agentID: "bridge", kind: "question", text: "Old question", requestID: "old"))
    replyStore.selection = "bridge"
    replyStore.stage("Answer")
    let before = replyStore.snapshot.agents.count
    replyStore.createAgent(provider: "Codex", directory: root.path, prompt: "Other task")
    check(replyStore.snapshot.agents.count == before, "creating during pending reply cannot orphan an unsent agent")
    let replacement = AgentEvent(agentID: "bridge", kind: "question", text: "Replacement", requestID: "replacement")
    try JSONEncoder().encode(replacement).write(to: replyStore.root.appendingPathComponent("events/new.json"))
    replyStore.commitPending()
    check(replyStore.selected?.requestID == "replacement" && !FileManager.default.fileExists(atPath: replyStore.root.appendingPathComponent("replies/\(BridgePaths.safeFilename("old")).json").path), "drain replacement bridge event before committing staged answer")
    replyStore.attachment = root.appendingPathComponent("unrelated.png")
    let priorComposer = replyStore.composerKey
    replyStore.draft = "Composer text"
    replyStore.createAgent(provider: "Claude", directory: root.path, prompt: "New task")
    check(replyStore.pending?.attachment == nil && replyStore.pending?.text == "New task" && replyStore.draft(for: priorComposer) == "Composer text", "new agent does not inherit unrelated composer attachment or draft")
    replyStore.shutdown()

    let candidates = [RoutingCandidate(codexAgent), RoutingCandidate(claudeAgent)]
    let valid = #"{"agentID":"observed:codex:external-codex","reason":"This session owns pricing.","confidence":0.94}"#
    let decision = try RoutingDecision.decode(Data(valid.utf8), candidates: candidates)
    check(decision.agentID == codexAgent.id, "validate model-selected recipient against candidate set")
    do {
        _ = try RoutingDecision.decode(Data(#"{"agentID":"unknown","reason":"No","confidence":0.8}"#.utf8), candidates: candidates)
        check(false, "reject invented routing recipient")
    } catch { check(true, "reject invented routing recipient") }
    do {
        _ = try RoutingDecision.decode(Data(#"{"agentID":null,"reason":"No","confidence":4}"#.utf8), candidates: candidates)
        check(false, "reject invalid model confidence")
    } catch { check(true, "reject invalid model confidence") }
    let noMatch = try RoutingDecision.decode(Data(#"{"agentID":null,"reason":"No matching session.","confidence":0.1}"#.utf8), candidates: candidates)
    check(noMatch.agentID == nil, "router can decline to select a recipient")
    check(candidates.allSatisfy { !$0.project.contains("/") && $0.latestMessage.count <= 600 }, "routing context uses bounded excerpts and project basename")
    var contextAgent = Agent(id: "context", name: "Codex", provider: "Codex", directory: "/missing/orca/workspaces/shop/checkout-fix", title: "Improve checkout", messages: [
        Message(role: "user", text: "Make checkout retry failed payments", date: now.addingTimeInterval(-60)),
        Message(role: "assistant", text: "Should I preserve the customer's cart?", date: now.addingTimeInterval(-50)),
        Message(role: "user", text: "yes", date: now.addingTimeInterval(-40)),
        Message(role: "system", text: "private system context", date: now.addingTimeInterval(-30)),
        Message(role: "tool", text: "private tool output", date: now.addingTimeInterval(-20))
    ])
    let context = ConversationContext(contextAgent)
    check(context.latestRequest?.text == "yes" && context.latestResponse == nil, "a new request never borrows the previous turn's answer")
    check(context.recentMessages.map(\.role) == ["user", "assistant", "user"], "conversation context excludes tool and system records")
    let contextual = RoutingCandidate(contextAgent)
    check(contextual.project == "shop" && contextual.worktree == "checkout-fix", "routing distinguishes project from worktree instead of sharing a basename")
    check(contextual.latestRequest == "yes" && contextual.recentMessages[1].text.contains("cart"), "short replies reach the router with the question they answer")
    let input = try JSONSerialization.jsonObject(with: RoutingService.input(text: "continue", candidates: [contextual], selectedAgentID: "context")) as! [String: Any]
    check(input["selectedAgentID"] as? String == "context", "routing preserves the explicitly selected conversation as context")
    let invalidInput = try JSONSerialization.jsonObject(with: RoutingService.input(text: "continue", candidates: [contextual], selectedAgentID: "untracked")) as! [String: Any]
    check(invalidInput["selectedAgentID"] is NSNull, "routing cannot disclose a selection outside the eligible candidates")
    contextAgent.messages += (0..<12).map { Message(role: "assistant", text: String(repeating: "x", count: 3000) + " \($0)") }
    let bounded = RoutingCandidate(contextAgent)
    check(bounded.recentMessages.count == 6 && bounded.recentMessages.allSatisfy { $0.text.count <= 400 } && bounded.latestRequest == "yes", "long progress streams retain the last user request within bounded routing context")
    check(ConversationContext.excerpt("First\n\n  second\tthird", limit: 12) == "First secon…", "list excerpts collapse whitespace and visibly mark truncation")
    check(ConversationContext(Agent(id: "empty", name: "Empty")).latestRequest == nil, "missing history never invents a user request")
    let encoded = String(decoding: try RoutingService.input(text: "continue", candidates: [contextual], selectedAgentID: nil), as: UTF8.self)
    check(!encoded.contains("private system") && !encoded.contains("private tool") && encoded.contains("T"), "routing payload contains public turn context without system or tool content")
    let routerCLI = root.appendingPathComponent("fake-router")
    try """
    #!/bin/sh
    printf '%s\\n' '{"type":"result","is_error":false,"structured_output":\(valid)}'
    """.write(to: routerCLI, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: routerCLI.path)
    let routed = try await RoutingService(executableOverride: routerCLI).suggest(text: "Fix pricing", candidates: candidates, directory: root.appendingPathComponent("router-test"))
    check(routed == decision, "routing subprocess returns validated structured decision")
    let args = RoutingService.arguments(prompt: "test")
    check(args.contains("--strict-mcp-config") && args.contains("--no-session-persistence") && args.contains("--disable-slash-commands") && args[args.firstIndex(of: "--tools")! + 1].isEmpty, "router CLI is isolated from tools and saved sessions")
    let localMatch = RecipientRecommendation.local(text: "Change pricing", candidates: candidates, selectedAgentID: claudeAgent.id)
    check(localMatch.agentID == codexAgent.id && localMatch.basis == .matchingWords && localMatch.reason.contains("pricing"), "typing a different task immediately recommends the matching conversation with a reason")
    check(RecipientRecommendation.local(text: "yes", candidates: candidates, selectedAgentID: claudeAgent.id).agentID == claudeAgent.id, "short follow-ups retain the current conversation")
    check(RecipientRecommendation.local(text: "", candidates: candidates, selectedAgentID: claudeAgent.id).agentID == claudeAgent.id, "empty Talk still shows the current recipient")
    var duplicateCandidate = candidates[0]; duplicateCandidate.id = "another-pricing"
    check(RecipientRecommendation.local(text: "pricing", candidates: candidates + [duplicateCandidate], selectedAgentID: codexAgent.id).agentID == nil, "equally relevant conversations require a choice instead of guessing")
    check(RecipientRecommendation.local(text: "please fix this", candidates: candidates, selectedAgentID: nil).agentID == nil, "generic words do not create an arbitrary recommendation")
    check(RecipientRecommendation.local(text: "yes", candidates: candidates, selectedAgentID: "removed").agentID == nil, "local recommendation never restores a removed recipient")
    check(RecipientRecommendation.local(text: "pricing", candidates: [], selectedAgentID: codexAgent.id).basis == .needsChoice, "no eligible agents produces an actionable empty recommendation")
    check(RecipientRecommendation.local(text: "preserve cart", candidates: [contextual] + candidates, selectedAgentID: nil).agentID == contextual.id, "recommendation can match the recent conversation question")
    let recommendationStore = Store(root: root.appendingPathComponent("recommendation-store"), demo: false, routingExecutable: routerCLI)
    recommendationStore.snapshot.agents = [codexAgent, claudeAgent]
    recommendationStore.tab = "Talk"; recommendationStore.selection = claudeAgent.id
    recommendationStore.draft = "Change pricing"
    let originalImage = root.appendingPathComponent("recommendation-image.png")
    recommendationStore.attachment = originalImage
    check(recommendationStore.recipientRecommendation.agentID == codexAgent.id && recommendationStore.pending == nil && recommendationStore.selection == claudeAgent.id, "visible recommendation neither switches the recipient nor sends")
    recommendationStore.useSuggestedRecipient()
    check(recommendationStore.selection == codexAgent.id && recommendationStore.draft == "Change pricing" && recommendationStore.attachment == originalImage && recommendationStore.pending == nil, "Use this selects the recommendation while preserving text and image without sending")
    recommendationStore.suggestRecipient()
    for _ in 0..<100 where recommendationStore.routing { try await Task.sleep(nanoseconds: 20_000_000) }
    check(recommendationStore.recipientRecommendation.basis == .ai && recommendationStore.routeDecision == decision && recommendationStore.pending == nil, "visible AI action goes through Store and subprocess to a validated recommendation without sending")
    recommendationStore.draft = "Checkout"
    check(recommendationStore.routeDecision == nil && recommendationStore.recipientRecommendation.agentID == claudeAgent.id, "editing the draft immediately replaces a stale AI result with the new match")
    recommendationStore.suggestRecipient(); recommendationStore.selection = claudeAgent.id
    try await Task.sleep(nanoseconds: 100_000_000)
    check(!recommendationStore.routing && recommendationStore.routeDecision == nil, "changing recipients cancels an in-flight AI recommendation")
    recommendationStore.routeDecision = decision
    recommendationStore.useSuggestedRecipient()
    check(recommendationStore.selection == codexAgent.id && recommendationStore.routeDecision == decision && recommendationStore.pending == nil, "accepting an AI recommendation keeps its explanation visible without sending")
    recommendationStore.selection = claudeAgent.id
    recommendationStore.routeDecision = decision
    recommendationStore.trackConversation(codexAgent.id, enabled: false)
    check(recommendationStore.recipientRecommendation.agentID != codexAgent.id, "removing tracking immediately removes that recipient recommendation")
    recommendationStore.routeDecision = decision
    recommendationStore.useSuggestedRecipient()
    check(recommendationStore.selection == claudeAgent.id && recommendationStore.pending == nil, "accepting a stale unavailable result never switches to an untracked agent")
    recommendationStore.shutdown()
    let forkAgent = Agent(id: "fork", name: "fork", provider: "Codex", managed: true, forkSessionID: "original-session")
    let forkArgs = try AgentRunner.arguments(agent: forkAgent, prompt: "--not-a-flag", image: nil)
    check(Array(forkArgs.prefix(3)) == ["exec", "fork", "original-session"] && Array(forkArgs.suffix(2)) == ["--", "--not-a-flag"], "Codex fork and literal prompt arguments")
    var claudeFork = forkAgent; claudeFork.provider = "Claude"
    check(try AgentRunner.arguments(agent: claudeFork, prompt: "Continue", image: nil).contains("--fork-session"), "Claude fork creates a separate session")
    var resumed = forkAgent; resumed.sessionID = "new-session"
    check(try AgentRunner.arguments(agent: resumed, prompt: "Next", image: nil).prefix(3) == ["exec", "resume", "new-session"], "subsequent turn resumes the new fork")
    var invalid = forkAgent; invalid.forkSessionID = "--dangerously-bypass-approvals-and-sandbox"
    do { _ = try AgentRunner.arguments(agent: invalid, prompt: "test", image: nil); check(false, "reject option-like session references") }
    catch { check(true, "reject option-like session references") }
    let captureRoot = root.appendingPathComponent("capture-test")
    var requestedPermission = false
    let denied = RegionCapture(permissionGranted: { false }, requestPermission: { requestedPermission = true })
    do { _ = try await denied.capture(to: captureRoot); check(false, "capture needs native permission") }
    catch { check(requestedPermission && !FileManager.default.fileExists(atPath: captureRoot.path), "capture requests permission before any screenshot process") }
    let cancelled = root.appendingPathComponent("fake-capture-cancel")
    try "#!/bin/sh\nexit 1\n".write(to: cancelled, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cancelled.path)
    let cancelledCapture = try await RegionCapture(executable: cancelled, permissionGranted: { true }).capture(to: captureRoot)
    check(cancelledCapture == nil, "Escape produces no screenshot attachment")
    // The synthetic image is generated locally; this test never reads the screen.
    let fixture = root.appendingPathComponent("pixel.png")
    try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a7XcAAAAASUVORK5CYII=")!.write(to: fixture)
    let success = root.appendingPathComponent("fake-capture-success")
    try "#!/bin/sh\nfor destination do :; done\ncp '\(fixture.path)' \"$destination\"\n".write(to: success, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: success.path)
    let capture = try unwrap(try await RegionCapture(executable: success, permissionGranted: { true }).capture(to: captureRoot), "capture result")
    let attributes = try FileManager.default.attributesOfItem(atPath: capture.path)
    check(attributes[.posixPermissions] as? Int == 0o600, "captured attachment is owner-only")
    let bounds = CGRect(x: -1440, y: 0, width: 1440, height: 900)
    let placed = WindowPlacement.constrained(CGRect(x: -399, y: -40, width: 740, height: 570), to: bounds)
    check(bounds.insetBy(dx: 12, dy: 12).contains(placed), "keep panel on screen after sheet or display changes")
}

private func unwrap<T>(_ value: T?, _ description: String) throws -> T {
    guard let value else { throw NSError(domain: "OpenOneTests", code: 1, userInfo: [NSLocalizedDescriptionKey: description]) }
    return value
}

@MainActor func runMultiHomeDiscoveryTests(root: URL, check: (Bool, String) -> Void) throws {
    let home = root.appendingPathComponent("multi-home")
    let standard = home.appendingPathComponent(".codex/sessions")
    let orca = home.appendingPathComponent("Library/Application Support/orca/codex-runtime-home/home/sessions")
    let cwd = root.appendingPathComponent("selected-project").path
    let defaults = SessionDiscovery.defaultCodexRoots(home: home, environment: [:])
    check(defaults == [standard, orca], "default discovery includes standard and Orca Codex homes")
    let configured = home.appendingPathComponent("custom")
    check(SessionDiscovery.defaultCodexRoots(home: home, environment: ["CODEX_HOME": configured.path]).count == 3,
          "custom Codex home supplements standard and Orca histories")
    check(SessionDiscovery.defaultCodexRoots(home: home, environment: ["CODEX_HOME": standard.deletingLastPathComponent().path]).count == 2,
          "configured standard Codex home is scanned only once")
    for (folder, id, title) in [(standard, "greeting", "Respond to greeting"), (orca, "logo", "Design open one logo")] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let metadata: [String: Any] = ["type": "session_meta", "payload": ["id": id, "cwd": cwd]]
        let done: [String: Any] = ["type": "event_msg", "payload": ["type": "task_complete", "last_agent_message": "Ready"]]
        var data = try JSONSerialization.data(withJSONObject: metadata); data.append(10)
        data.append(try JSONSerialization.data(withJSONObject: done)); data.append(10)
        try data.write(to: folder.appendingPathComponent("\(id).jsonl"))
        try JSONSerialization.data(withJSONObject: ["id": id, "thread_name": title]).write(to: folder.deletingLastPathComponent().appendingPathComponent("session_index.jsonl"))
    }
    let scanner = SessionDiscovery(codexRoot: standard, claudeRoot: home.appendingPathComponent("empty"), additionalCodexRoots: [orca, standard])
    let result = scanner.scan(trackedWorktreePaths: [cwd])
    check(result.agents.count == 2 && Set(result.agents.map(\.title)) == ["Respond to greeting", "Design open one logo"],
          "both Codex homes contribute conversations and their own saved titles")
    check(result.agents.first { $0.sessionID == "logo" }?.providerHome == orca.deletingLastPathComponent().path,
          "Orca conversation retains its native provider home for resume")
    check(scanner.scan(trackedWorktreePaths: [cwd]).agents == result.agents, "cached multi-home discovery preserves title and provider home")
    check(scanner.scan(trackedWorktreePaths: ["/different/checkout"]).agents.isEmpty, "additional Codex home still respects tracked checkout filter")
    let encoded = try JSONEncoder().encode(Snapshot(agents: result.agents))
    check(try JSONDecoder().decode(Snapshot.self, from: encoded).agents == result.agents, "provider home persists with discovered history")
    let legacy = Agent(id: "legacy", name: "Legacy")
    check(try JSONDecoder().decode(Agent.self, from: JSONEncoder().encode(legacy)).providerHome == nil, "legacy agent without provider home still decodes")
}

@MainActor func runLiveTranscriptTests(root: URL, check: (Bool, String) -> Void) async throws {
    let folder = root.appendingPathComponent("live-transcripts")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("live.jsonl")
    let now = Date(), stamp = ISO8601DateFormatter().string(from: Date())
    let header = "{\"timestamp\":\"\(stamp)\",\"type\":\"session_meta\",\"payload\":{\"id\":\"live-refresh\",\"cwd\":\"/test/live\"}}\n"
    let done = "{\"timestamp\":\"\(stamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"last_agent_message\":\"Fresh answer\"}}\n"
    try (header + done).write(to: file, atomically: true, encoding: .utf8)
    var original = Agent(id: "observed:codex:live-refresh", name: "Live", provider: "Codex", directory: "/test/live", state: .working,
                         title: "Custom name", sessionID: "live-refresh", updatedAt: now.addingTimeInterval(-2), sourcePath: file.path, providerHome: "/original/home")
    let refreshed = try unwrap(SessionDiscovery.refresh(original), "live refresh")
    check(refreshed.messages.last?.text == "Fresh answer" && refreshed.state == .done, "live reader picks up new answer without full provider scan")
    check(refreshed.providerHome == original.providerHome && refreshed.title == original.title && refreshed.id == original.id,
          "live reader preserves native destination and custom title")
    check(SessionDiscovery.refresh(refreshed) == nil, "unchanged live history skips parsing")
    var other = original; other.sessionID = "different-thread"
    check(SessionDiscovery.refresh(other) == nil, "replaced transcript cannot redirect live conversation")
    let link = folder.appendingPathComponent("link.jsonl")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    other = original; other.sourcePath = link.path
    check(SessionDiscovery.refresh(other) == nil, "live reader rejects symbolic-link transcript")
    try (header + String(repeating: "x", count: 2_200_000) + "\n" + done).write(to: file, atomically: true, encoding: .utf8)
    check(SessionDiscovery.refresh(original)?.messages.last?.text == "Fresh answer", "live refresh bounds reads while retaining metadata and latest output")
    try (header + done).write(to: file, atomically: true, encoding: .utf8)
    let store = Store(root: folder.appendingPathComponent("store"))
    defer { store.shutdown() }
    var unrelated = original; unrelated.id = "unrelated"; unrelated.sessionID = "unrelated"; unrelated.sourcePath = nil
    store.snapshot.agents = [original, unrelated]; store.selection = original.id
    let started = Date()
    store.refreshLiveTranscripts()
    for _ in 0..<100 {
        if store.agent(for: original.id)?.state == .done { break }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    let elapsed = Date().timeIntervalSince(started)
    check(store.agent(for: original.id)?.messages.last?.text == "Fresh answer" && elapsed < 1,
          "selected transcript reaches Store in under one second without 15-second scan interval")
    print(String(format: "TIMING: live transcript to Store %.3fs", elapsed))
    check(store.agent(for: unrelated.id)?.state == .working, "partial live refresh never marks other conversations stale")
    store.snapshot.agents = [original]; store.setDiscoveryEnabled(false); store.refreshLiveTranscripts()
    try await Task.sleep(nanoseconds: 50_000_000)
    check(store.agent(for: original.id)?.messages.isEmpty == true, "disabled discovery also disables live transcript reads")
    store.setDiscoveryEnabled(true)
    store.trackConversation(original.id, enabled: false)
    store.refreshLiveTranscripts()
    try await Task.sleep(nanoseconds: 50_000_000)
    check(store.agent(for: original.id)?.messages.isEmpty == true, "removed conversations stay excluded from live refresh")
    store.trackConversation(original.id, enabled: true)
    original.archived = true; store.snapshot.agents = [original]; store.refreshLiveTranscripts()
    try await Task.sleep(nanoseconds: 50_000_000)
    check(store.agent(for: original.id)?.archived == true && store.agent(for: original.id)?.messages.isEmpty == true,
          "live refresh cannot restore an archived conversation")
}
