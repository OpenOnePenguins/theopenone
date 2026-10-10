import Foundation
import OneCore

@MainActor func runResumeTests(root: URL, check: (Bool, String) -> Void) async throws {
    let fixture = root.appendingPathComponent("resume-cli")
    try """
    #!/bin/sh
    printf '%s\\n' "$@" > resume-arguments.txt
    printf '%s\\n' "$CODEX_HOME" > resume-home.txt
    if [ "$1" = exec ]; then
      printf '%s\\n' '{"type":"thread.started","thread_id":"original-Codex"}' '{"type":"item.completed","item":{"type":"agent_message","text":"Continued original history"}}'
    else
      printf '%s\\n' '{"type":"system","session_id":"original-Claude"}' '{"type":"assistant","message":{"content":[{"type":"text","text":"Continued original history"}]}}'
    fi
    """.write(to: fixture, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
    for provider in ["Codex", "Claude"] {
        let folder = root.appendingPathComponent("resume-\(provider)")
        let store = Store(root: folder, runnerExecutable: fixture)
        defer { store.shutdown() }
        let transcript = folder.appendingPathComponent("original.jsonl")
        try Data("saved history\n".utf8).write(to: transcript)
        let observed = Agent(id: "observed-\(provider)", name: "Original", provider: provider, directory: folder.path,
                             state: .done, messages: [Message(role: "assistant", text: "Earlier answer")],
                             sessionID: "original-\(provider)", updatedAt: Date(), sourcePath: transcript.path, providerHome: provider == "Codex" ? folder.appendingPathComponent("Orca home").path : nil)
        store.snapshot.agents = [observed, Agent(id: "other", name: "Other", directory: folder.path)]
        store.selection = observed.id; store.draft = "Continue my work"
        store.stage(store.draft)
        check(store.pending?.resume?.sessionID == observed.sessionID && store.selected?.managed == false && !store.showNewAgent,
              "\(provider): send stages original session without adopting or opening Fork")
        store.undo()
        check(store.pending == nil && store.selected == observed && store.draft == "Continue my work",
              "\(provider): undo preserves observed history and draft")
        store.stage(store.draft, agentID: observed.id, composerKeyOverride: "agent:\(observed.id)")
        store.selection = "other"
        store.commitPending()
        for _ in 0..<100 {
            if store.agent(for: observed.id)?.state != .working { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let continued = store.agent(for: observed.id)!
        let args = try String(contentsOf: folder.appendingPathComponent("resume-arguments.txt"), encoding: .utf8).components(separatedBy: "\n").filter { !$0.isEmpty }
        check(continued.managed && continued.sessionID == observed.sessionID && continued.forkSessionID == nil && continued.state == .done,
              "\(provider): fixture subprocess resumes original identity and completes")
        check(continued.messages.map(\.text) == ["Earlier answer", "Continue my work", "Continued original history"] && store.snapshot.agents.count == 2,
              "\(provider): keeps history in same card without a duplicate conversation")
        check(store.agent(for: "other")?.messages.isEmpty == true && store.draft(for: "agent:\(observed.id)").isEmpty,
              "\(provider): popout targets captured conversation despite selection change")
        let expected = provider == "Codex" ? ["exec", "resume", "original-Codex", "--json", "--", "Continue my work"] : ["-p", "--verbose", "--output-format", "stream-json", "--resume", "original-Claude", "--", "Continue my work"]
        if provider == "Codex" {
            let environmentHome = try String(contentsOf: folder.appendingPathComponent("resume-home.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            check(environmentHome == observed.providerHome, "Codex resume subprocess uses the discovered provider home")
        }
        check(args == expected, "\(provider): native arguments resume exactly this ID without any fork flags")
        store.mergeDiscovered(DiscoveryResult(agents: [observed]))
        check(store.agent(for: observed.id)?.messages == continued.messages && store.snapshot.agents.count == 2,
              "\(provider): background discovery cannot overwrite resumed conversation")
        store.save(); store.shutdown()
        let restored = Store(root: folder, runnerExecutable: fixture)
        check(restored.agent(for: observed.id)?.managed == true && restored.agent(for: observed.id)?.sessionID == observed.sessionID,
              "\(provider): resumed identity survives restart")
        check(restored.agent(for: observed.id)?.providerHome == observed.providerHome, "\(provider): provider home survives restart")
        restored.createAgent(provider: provider, directory: folder.path, prompt: "Separate branch", forkFrom: restored.agent(for: observed.id))
        check(restored.selected?.providerHome == observed.providerHome && restored.selected?.forkSessionID == observed.sessionID, "\(provider): explicit fork retains source provider home")
        restored.undo(); restored.shutdown()
    }
    let folder = root.appendingPathComponent("resume-rejections")
    let store = Store(root: folder, runnerExecutable: fixture)
    defer { store.shutdown() }
    let transcript = folder.appendingPathComponent("original.jsonl")
    try Data("saved history\n".utf8).write(to: transcript)
    var original = Agent(id: "original", name: "Original", provider: "Codex", directory: folder.path, state: .done,
                         sessionID: "original-Codex", updatedAt: Date(), sourcePath: transcript.path)
    func reset() { store.undo(); store.notice = nil; store.snapshot.agents = [original]; store.selection = original.id; store.draft = "Keep this draft" }
    for state in [AgentState.working, .waiting] {
        reset(); store.snapshot.agents[0].state = state
        store.stage(store.draft)
        check(store.pending == nil && !store.snapshot.agents[0].managed, "resume refuses observed \(state.rawValue) conversation")
    }
    for reference in [nil, "", "--invalid"] as [String?] {
        reset(); store.snapshot.agents[0].sessionID = reference; store.stage(store.draft)
        check(store.pending == nil, "resume requires valid native session ID: \(reference ?? "nil")")
    }
    reset(); store.snapshot.agents[0].provider = "Unsupported"; store.stage(store.draft)
    check(store.pending == nil, "resume rejects unsupported provider")
    reset(); store.snapshot.agents[0].directory = folder.appendingPathComponent("missing").path; store.stage(store.draft)
    check(store.pending == nil && store.draft == "Keep this draft", "resume rejects missing project and keeps draft")
    reset(); store.snapshot.agents[0].sourcePath = folder.appendingPathComponent("missing.jsonl").path; store.stage(store.draft)
    check(store.pending == nil, "resume rejects unavailable transcript")
    reset(); store.snapshot.agents.append(Agent(id: "connected", name: "Connected", provider: "Codex", directory: folder.path, sessionID: original.sessionID, managed: true)); store.stage(store.draft)
    check(store.pending == nil, "resume rejects a duplicate connected owner")
    for field in ["session", "directory", "provider", "provider-home", "state"] {
        reset(); store.stage(store.draft)
        switch field {
        case "session": store.snapshot.agents[0].sessionID = "replacement"
        case "directory": store.snapshot.agents[0].directory = root.path
        case "provider": store.snapshot.agents[0].provider = "Claude"
        case "provider-home": store.snapshot.agents[0].providerHome = "/changed/home"
        default: store.snapshot.agents[0].state = .working
        }
        store.commitPending()
        check(!store.snapshot.agents[0].managed && store.snapshot.agents[0].messages.isEmpty && store.draft == "Keep this draft",
              "resume cancels changed \(field) during Undo window")
    }
    reset(); store.stage(store.draft)
    try Data("new external turn\n".utf8).write(to: transcript)
    store.commitPending()
    check(!store.snapshot.agents[0].managed && store.draft == "Keep this draft" && store.notice?.contains("changed") == true,
          "resume cancels transcript activity during Undo window")
    store.stage(store.draft)
    check(store.pending == nil && store.notice?.contains("newer activity") == true, "resume refuses history newer than displayed messages")
    original.updatedAt = Date()
    reset(); store.stage(store.draft); store.trackConversation(original.id, enabled: false); store.commitPending()
    check(!store.snapshot.agents[0].managed && store.draft(for: "agent:original") == "Keep this draft", "removing conversation cancels pending resume")
    let unavailable = Store(root: folder.appendingPathComponent("missing-cli"), runnerExecutable: folder.appendingPathComponent("not-installed"))
    unavailable.snapshot.agents = [original]; unavailable.selection = original.id; unavailable.stage("Continue")
    check(unavailable.pending == nil && !unavailable.snapshot.agents[0].managed, "missing CLI cannot adopt session or consume draft")
    unavailable.shutdown()
}

@MainActor func runResumeFailureTests(root: URL, check: (Bool, String) -> Void) async throws {
    for mode in ["failure", "wrong-session"] {
        let folder = root.appendingPathComponent("resume-\(mode)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fixture = folder.appendingPathComponent("cli")
        let output = mode == "failure" ? "{\"type\":\"turn.failed\",\"error\":{\"message\":\"Sign-in required\"}}" : "{\"type\":\"thread.started\",\"thread_id\":\"unexpected-fork\"}"
        try "#!/bin/sh\nprintf '%s\\n' '\(output)'\n".write(to: fixture, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
        let transcript = folder.appendingPathComponent("history.jsonl")
        try Data("saved history\n".utf8).write(to: transcript)
        let store = Store(root: folder, runnerExecutable: fixture)
        defer { store.shutdown() }
        store.snapshot.agents = [Agent(id: "original", name: "Original", provider: "Codex", directory: folder.path,
                                       state: .done, sessionID: "original-Codex", updatedAt: Date(), sourcePath: transcript.path)]
        store.selection = "original"; store.draft = "Continue"
        store.stage(store.draft); store.commitPending()
        for _ in 0..<100 {
            if store.selected?.messages.last?.text.contains("Agent exited") == true { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        check(store.selected?.state == .offline && store.selected?.sessionID == "original-Codex" && store.snapshot.agents.count == 1,
              "resume \(mode) keeps original identity and exposes failed state")
        check(store.selected?.messages.contains { $0.role == "system" && $0.text.contains(mode == "failure" ? "Sign-in required" : "different session") } == true,
              "resume \(mode) exposes actionable CLI error")
        store.stage("Retry")
        check(store.pending?.agentID == "original" && store.pending?.resume == nil, "resume \(mode) permits explicit retry without forking")
        store.undo()
    }
}

@MainActor func runWriterConflictTests(root: URL, check: (Bool, String) -> Void) async throws {
    let folder = root.appendingPathComponent("writer-conflicts")
    let home = folder.appendingPathComponent("Orca home")
    let lockFolder = home.appendingPathComponent("thread-writer-locks")
    try FileManager.default.createDirectory(at: lockFolder, withIntermediateDirectories: true)
    let session = "89152b38-5fe4-4e14-bdb8-083210fd0cb9"
    let lock = lockFolder.appendingPathComponent(session + ".lock")
    let transcript = folder.appendingPathComponent("history.jsonl")
    try Data("saved conversation\n".utf8).write(to: transcript)
    let original = Agent(id: "observed-writer", name: "Original", provider: "Codex", directory: folder.path, state: .done,
                         messages: [Message(role: "assistant", text: "Earlier answer")], sessionID: session,
                         updatedAt: Date(), sourcePath: transcript.path, providerHome: home.path)
    check(try !AgentRunner.hasActiveWriter(original) && !FileManager.default.fileExists(atPath: lock.path), "writer check never creates a missing lock file")
    try Data().write(to: lock)
    check(try !AgentRunner.hasActiveWriter(original), "unlocked stale lock file does not block resume")
    func acquire() async throws -> (Process, Pipe) {
        let ready = folder.appendingPathComponent(UUID().uuidString)
        let pipe = Pipe(), process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", "import sys,fcntl; f=open(sys.argv[1],'a+b'); fcntl.flock(f,fcntl.LOCK_EX); open(sys.argv[2],'w').close(); sys.stdin.read()", lock.path, ready.path]
        process.standardInput = pipe
        try process.run()
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: ready.path) { return (process, pipe) }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        process.terminate(); throw CocoaError(.fileReadUnknown)
    }
    func release(_ holder: (Process, Pipe)) { try? holder.1.fileHandleForWriting.close(); holder.0.waitUntilExit() }
    let holder = try await acquire()
    check(try AgentRunner.hasActiveWriter(original), "real external exclusive writer lock is detected")
    var otherHome = original; otherHome.providerHome = folder.appendingPathComponent("other-home").path
    check(try !AgentRunner.hasActiveWriter(otherHome), "writer checks use the conversation's exact provider home")
    var claude = original; claude.provider = "Claude"
    check(try !AgentRunner.hasActiveWriter(claude), "Codex writer locks do not block Claude sessions")
    let store = Store(root: folder.appendingPathComponent("store"), runnerExecutable: URL(fileURLWithPath: "/usr/bin/false"))
    defer { store.shutdown() }
    store.snapshot.agents = [original]; store.selection = original.id; store.draft = "Continue this work"
    store.stage(store.draft)
    check(store.pending?.queueTarget?.sessionID == session && store.draft == "Continue this work" && store.selected?.managed == false,
          "active writer stages native queue without adopting the session or losing draft")
    store.undo()
    store.snapshot.agents[0].managed = true; store.snapshot.agents[0].state = .offline
    store.stage(store.draft)
    check(store.pending?.queueTarget?.sessionID == session, "existing app-managed resume queues through external owner")
    store.undo()
    store.snapshot.agents[0] = original
    let runner = AgentRunner(executableOverride: URL(fileURLWithPath: "/usr/bin/false"))
    let blocked = await withCheckedContinuation { continuation in
        var busy = false
        runner.start(agent: original, prompt: "Should not launch", image: nil) { update in
            if case .writerBusy = update { busy = true }
            if case .finished(let code) = update { continuation.resume(returning: busy && code != 0) }
        }
    }
    check(blocked, "runner independently refuses to launch into a held writer lock")
    release(holder)
    check(try !AgentRunner.hasActiveWriter(original) && FileManager.default.fileExists(atPath: lock.path), "exiting owner makes the session available without deleting its lock file")
    store.stage(store.draft)
    check(store.pending != nil, "released writer allows explicit retry")
    let secondHolder = try await acquire()
    store.commitPending()
    check(store.pending == nil && store.selected?.managed == false && store.selected?.messages == original.messages && store.draft == "Continue this work",
          "writer acquired during Undo queues without adopting or changing observed history")
    release(secondHolder)
    let conflict = "thread-store conflict: thread \(session) already has an active writer"
    check(AgentRunner.isWriterConflict(conflict) && !AgentRunner.isWriterConflict("quota exceeded"), "writer conflict classification does not treat unrelated errors as unsent ownership conflicts")
    // Exercise a race reported by the CLI after our preflight succeeded.
    for stream in ["stderr", "json"] {
        let fixture = folder.appendingPathComponent("busy-\(stream)")
        let output = stream == "stderr" ? "printf '%s\\n' '\(conflict)' >&2\nexit 1" : "printf '%s\\n' '{\"type\":\"turn.failed\",\"error\":{\"message\":\"\(conflict)\"}}'"
        try "#!/bin/sh\n\(output)\n".write(to: fixture, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
        let failed = Store(root: folder.appendingPathComponent("race-\(stream)"), runnerExecutable: fixture)
        failed.snapshot.agents = [original]; failed.selection = original.id; failed.draft = "Keep my rejected prompt"
        failed.stage(failed.draft); failed.commitPending()
        check(failed.draft == "Keep my rejected prompt", "\(stream): draft remains until the CLI accepts the session")
        for _ in 0..<100 {
            if failed.notice == AgentRunner.writerBusyMessage { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        check(failed.selected?.managed == false && failed.selected?.messages == original.messages && failed.draft == "Keep my rejected prompt",
              "\(stream): native writer conflict rolls back takeover and unsent message, preserving draft")
        check(failed.notice == AgentRunner.writerBusyMessage && failed.selected?.state == .unknown,
              "\(stream): native conflict shows exit instructions instead of a generic CLI failure")
        failed.shutdown()
    }
    let acceptedCLI = folder.appendingPathComponent("accepted-conflict")
    try """
    #!/bin/sh
    printf '%s\\n' '{"type":"thread.started","thread_id":"\(session)"}'
    printf '%s\\n' '\(conflict)' >&2
    exit 1
    """.write(to: acceptedCLI, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: acceptedCLI.path)
    let accepted = Store(root: folder.appendingPathComponent("accepted"), runnerExecutable: acceptedCLI)
    accepted.snapshot.agents = [original]; accepted.selection = original.id; accepted.draft = "Already accepted"
    accepted.stage(accepted.draft); accepted.commitPending()
    for _ in 0..<100 {
        if accepted.selected?.messages.last?.text.contains("Agent exited") == true { break }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    check(accepted.selected?.managed == true && accepted.selected?.messages.contains { $0.role == "user" && $0.text == "Already accepted" } == true && accepted.draft.isEmpty,
          "writer-like error after native session acceptance cannot falsely roll back a delivered prompt")
    accepted.shutdown()
    let acceptedRestart = Store(root: folder.appendingPathComponent("accepted"))
    check(acceptedRestart.agent(for: original.id)?.managed == true && acceptedRestart.draft(for: "agent:" + original.id).isEmpty,
          "restart cannot recover a prompt that the provider already accepted")
    acceptedRestart.shutdown()
    // Repair a failed takeover persisted by an earlier release.
    let legacyRoot = folder.appendingPathComponent("legacy")
    let legacy = Store(root: legacyRoot)
    var rejected = original; rejected.managed = true; rejected.state = .offline
    rejected.messages += [Message(role: "user", text: "Recover this exact prompt"), Message(role: "system", text: conflict), Message(role: "system", text: "Agent exited with status 1.")]
    legacy.snapshot.agents = [rejected]; legacy.save(); legacy.shutdown()
    let repaired = Store(root: legacyRoot)
    check(repaired.agent(for: original.id)?.managed == false && repaired.agent(for: original.id)?.messages == original.messages,
          "restart repairs an earlier rejected takeover without retaining an unsent history bubble")
    check(repaired.draft(for: "agent:" + original.id) == "Recover this exact prompt", "restart restores exact rejected prompt into persistent composer")
    repaired.shutdown()
    let again = Store(root: legacyRoot)
    check(again.draft(for: "agent:" + original.id) == "Recover this exact prompt", "recovered prompt survives another restart")
    again.shutdown()
    let editedRoot = folder.appendingPathComponent("edited-legacy")
    let edited = Store(root: editedRoot)
    edited.snapshot.agents = [rejected]; edited.selection = original.id; edited.draft = "Newer edited draft"; edited.shutdown()
    let kept = Store(root: editedRoot)
    check(kept.draft(for: "agent:" + original.id) == "Newer edited draft" && kept.agent(for: original.id)?.messages == rejected.messages,
          "legacy recovery never overwrites an edited draft or discards its rejected prompt history")
    kept.shutdown()
}

@MainActor func runCodexQueueTests(root: URL, check: (Bool, String) -> Void) async throws {
    let folder = root.appendingPathComponent("codex-queue")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let session = "c06c4186-fd5a-4d6c-972b-d4d2215ac001"
    let receiptID = "c06c4186-fd5a-4d6c-972b-d4d2215ac002"
    let fixture = folder.appendingPathComponent("queue-cli")
    try """
    #!/bin/sh
    printf '%s\\n' "$@" > queue-arguments.txt
    printf '%s\\n' "$CODEX_HOME" > queue-home.txt
    sleep 0.1
    printf '%s\\n' 'Queued message \(receiptID) for thread \(session).'
    """.write(to: fixture, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
    let transcript = folder.appendingPathComponent("history.jsonl")
    try Data("original\n".utf8).write(to: transcript)
    let agent = Agent(id: "queued", name: "Live Codex", provider: "Codex", directory: folder.path, state: .working,
                      messages: [Message(role: "assistant", text: "Existing history")], sessionID: session,
                      sourcePath: transcript.path, providerHome: folder.appendingPathComponent("Orca home").path)
    let literal = "--literal 'text' $(never-run)\nsecond line"
    let args = try AgentRunner.queueArguments(agent: agent, prompt: literal, image: URL(fileURLWithPath: "/tmp/image with spaces.png"))
    check(args == ["queue", "--thread", session, "--message=" + literal, "--image", "/tmp/image with spaces.png"], "native queue pins UUID and preserves literal prompt and image arguments")
    var invalid = agent; invalid.sessionID = "--option"
    do { _ = try AgentRunner.queueArguments(agent: invalid, prompt: "x", image: nil); check(false, "queue rejects invalid native identity") }
    catch { check(true, "queue rejects invalid native identity") }
    let store = Store(root: folder.appendingPathComponent("store"), runnerExecutable: fixture)
    defer { store.shutdown() }
    func reset() { store.undo(); store.notice = nil; store.snapshot.agents = [agent]; store.selection = agent.id; store.draft = literal }
    reset()
    check(store.canSend(to: agent), "working observed Codex permits queue submission")
    store.stage(store.draft)
    check(store.pending?.queueTarget?.sessionID == session && store.pending?.resume == nil, "live queue captures recipient without resuming")
    store.undo()
    check(store.selected == agent && store.draft == literal && !FileManager.default.fileExists(atPath: folder.appendingPathComponent("queue-arguments.txt").path), "Undo prevents queue launch and preserves history and draft")
    store.stage(store.draft)
    store.snapshot.agents[0].providerHome = "/different/home"
    store.commitPending()
    check(store.draft == literal && store.notice?.contains("conversation changed") == true, "queue cancels if provider home changes during Undo")
    reset(); store.stage(store.draft); store.snapshot.agents[0].state = .waiting; store.commitPending()
    check(store.draft == literal && store.notice?.contains("conversation changed") == true, "queue rechecks newly waiting approval before delivery")
    reset(); store.stage(store.draft)
    // A running agent can write new output during Undo without invalidating the destination.
    try Data("new transcript output\n".utf8).write(to: transcript)
    store.snapshot.agents[0].messages.append(Message(role: "assistant", text: "New output"))
    store.snapshot.agents.append(Agent(id: "other", name: "Other")); store.selection = "other"
    store.commitPending()
    check(store.draft(for: "agent:queued") == literal && !store.canSend(to: agent), "queue keeps draft until receipt and blocks duplicate in-flight submission")
    for _ in 0..<150 {
        if store.notice?.hasPrefix("Queued in Codex") == true { break }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    check(store.notice?.hasPrefix("Queued in Codex") == true && store.draft(for: "agent:queued").isEmpty, "matching native queue receipt clears only delivered draft")
    check(store.agent(for: agent.id)?.managed == false && store.agent(for: agent.id)?.state == .working && store.agent(for: agent.id)?.messages.count == 2,
          "queue acceptance never adopts session, fabricates reply bubble, or marks turn done")
    check(store.agent(for: "other")?.messages.isEmpty == true, "queue uses captured chat despite selection change")
    let captured = try String(contentsOf: folder.appendingPathComponent("queue-arguments.txt"), encoding: .utf8)
    let capturedHome = try String(contentsOf: folder.appendingPathComponent("queue-home.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    check(captured.hasPrefix("queue\n--thread\n\(session)\n--message=\(literal)\n") && capturedHome == agent.providerHome, "queue subprocess uses exact arguments and discovered Codex home")
    reset(); store.stage(store.draft); store.commitPending(); store.draft = "Newer edit"
    for _ in 0..<150 {
        if store.notice?.hasPrefix("Queued in Codex") == true { break }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    check(store.draft == "Newer edit", "queue receipt cannot erase text edited while delivery is in flight")
    for mode in ["error", "wrong-thread", "no-receipt"] {
        let cli = folder.appendingPathComponent(mode)
        let script = mode == "error" ? "echo 'Queue unavailable' >&2\nexit 1" : mode == "wrong-thread" ? "echo 'Queued message \(receiptID) for thread \(receiptID).'" : "exit 0"
        try "#!/bin/sh\n\(script)\n".write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        let failed = Store(root: folder.appendingPathComponent("store-" + mode), runnerExecutable: cli)
        failed.snapshot.agents = [agent]; failed.selection = agent.id; failed.draft = literal
        failed.stage(failed.draft); failed.commitPending()
        for _ in 0..<150 {
            if failed.notice?.contains("could not confirm") == true { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        check(failed.notice?.contains("could not confirm") == true && failed.draft == literal && failed.selected == agent,
              "\(mode): unconfirmed queue preserves draft, ownership, state and history")
        failed.shutdown()
    }
}
