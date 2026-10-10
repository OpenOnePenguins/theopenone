import Foundation
import OneCore

@MainActor func runHerdrTests(root: URL, check: (Bool, String) -> Void) async throws {
    let folder = root.appendingPathComponent("herdr-fixture")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let executable = folder.appendingPathComponent("herdr")
    let fixture = #"""
    #!/usr/bin/env python3
    import json, os, sys, time
    root = os.path.dirname(__file__)
    args = sys.argv[1:]
    with open(os.path.join(root, 'calls.jsonl'), 'a') as f:
        f.write(json.dumps(args) + '\n')
    modefile = os.path.join(root, 'mode')
    mode = open(modefile).read() if os.path.exists(modefile) else 'normal'
    if mode == 'timeout':
        time.sleep(10)
    if mode == 'large':
        print('x' * 1100000)
        sys.exit(0)
    if mode == 'error':
        print(json.dumps({'error': {'code': 'not_found', 'message': 'fixture pane missing'}}), file=sys.stderr)
        sys.exit(1)
    if mode == 'bad':
        print('{}')
        sys.exit(0)
    if args == ['session', 'list', '--json']:
        print(json.dumps({'sessions': [{'name': 'test', 'running': True, 'default': False, 'socket_path': '/fixture/socket', 'session_dir': '/fixture'}]}))
        sys.exit(0)
    assert args[:2] == ['--session', 'test'], args
    command = args[2:]
    agent = {'pane_id': 'w1:p1', 'terminal_id': 'replacement' if mode == 'replaced' else 'terminal-1', 'agent_status': 'blocked' if mode == 'blocked' else 'working' if mode == 'working' else 'idle', 'agent': 'codex', 'name': 'test-agent', 'cwd': '/fixture'}
    agent['agent_session'] = {'source': 'codex', 'agent': 'codex', 'kind': 'session_id', 'value': 'new-session' if mode == 'new-session' else 'session-1'}
    if command == ['agent', 'list']:
        result = {'type': 'agent_list', 'agents': [agent]}
    elif command == ['agent', 'get', 'w1:p1']:
        result = {'type': 'agent_info', 'agent': agent}
    elif command == ['agent', 'read', 'w1:p1', '--source', 'recent-unwrapped', '--lines', '120']:
        print('Terminal output\nReady for input')
        sys.exit(0)
    elif command[:3] == ['agent', 'prompt', 'w1:p1']:
        assert len(command) == 4
        result = {'type': 'agent_prompted', 'agent': agent}
    elif command[:3] == ['agent', 'send-keys', 'w1:p1'] and command[3] in ['up', 'down', 'enter', 'esc']:
        result = {'type': 'ok'}
    else:
        raise Exception(str(args))
    print(json.dumps({'id': 'fixture', 'result': result}))
    """#
    try fixture.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    func mode(_ value: String) throws { try value.write(to: folder.appendingPathComponent("mode"), atomically: true, encoding: .utf8) }
    func calls() throws -> [[String]] {
        try String(contentsOf: folder.appendingPathComponent("calls.jsonl")).split(separator: "\n").map { try JSONDecoder().decode([String].self, from: Data($0.utf8)) }
    }
    let service = HerdrService(executableOverride: executable, timeout: 2)
    let sessions = try await service.sessions()
    check(sessions.count == 1 && sessions[0].name == "test" && sessions[0].running, "Herdr session discovery decodes public CLI shape")
    let agents = try await service.agents(session: "test")
    check(agents.first?.terminalID == "terminal-1" && agents.first?.provider == "Codex", "Herdr agent list decodes identity and provider")
    let text = try await service.read(session: "test", pane: "w1:p1")
    check(text.contains("Ready for input"), "Herdr read consumes plain terminal output")
    let prompt = "Use 'quotes' and \"spaces\"\n$(touch /not-executed) --session other"
    _ = try await service.prompt(session: "test", pane: "w1:p1", terminalID: "terminal-1", text: prompt)
    let history = try calls()
    check(history.last == ["--session", "test", "agent", "prompt", "w1:p1", prompt], "Herdr prompt stays a single argument with explicit session")
    check(history.dropLast().last == ["--session", "test", "agent", "get", "w1:p1"], "Herdr mutation rechecks live occupant identity")
    _ = try await service.prompt(session: "test", pane: "w1:p1", terminalID: "terminal-1", text: "--session=other")
    check((try calls()).last?.last == "\n--session=other", "Herdr global selector syntax remains literal prompt text")
    try mode("replaced")
    do { _ = try await service.prompt(session: "test", pane: "w1:p1", terminalID: "terminal-1", text: "task"); check(false, "Herdr rejects replaced pane occupant") }
    catch { check((try calls()).last?[3] == "get", "Herdr rejects replaced pane occupant before submission") }
    try mode("blocked")
    do { _ = try await service.prompt(session: "test", pane: "w1:p1", terminalID: "terminal-1", text: "task"); check(false, "Herdr rejects blocked agent") }
    catch { check((try calls()).last?[3] == "get", "Herdr blocked approval receives no prompt") }
    try await service.sendKey(session: "test", pane: "w1:p1", terminalID: "terminal-1", key: "down", expectedIdentity: agents[0].identityFingerprint)
    check((try calls()).last == ["--session", "test", "agent", "send-keys", "w1:p1", "down"], "Herdr blocked dialog accepts explicit supported navigation key")
    let beforeInvalidKey = try calls().count
    do { try await service.sendKey(session: "test", pane: "w1:p1", terminalID: "terminal-1", key: "ctrl+c"); check(false, "Herdr rejects arbitrary approval key") }
    catch { check(try calls().count == beforeInvalidKey, "Herdr rejects arbitrary approval key before launching CLI") }
    try mode("normal")
    do { try await service.sendKey(session: "test", pane: "w1:p1", terminalID: "terminal-1", key: "enter"); check(false, "Herdr rejects approval on nonblocked agent") }
    catch { check((try calls()).last?[3] == "get", "Herdr rejects approval key when dialog is gone") }
    try mode("new-session")
    do { _ = try await service.prompt(session: "test", pane: "w1:p1", terminalID: "terminal-1", text: "task", expectedIdentity: agents[0].identityFingerprint); check(false, "Herdr detects same-terminal native session replacement") }
    catch { check((try calls()).last?[3] == "get", "Herdr native session replacement receives no prompt") }
    try mode("working")
    try await service.interrupt(session: "test", pane: "w1:p1", terminalID: "terminal-1")
    check((try calls()).last == ["--session", "test", "agent", "send-keys", "w1:p1", "esc"], "Herdr interrupt sends Escape only to explicit target")
    try mode("error")
    do { _ = try await service.agents(session: "test"); check(false, "Herdr reports stderr API error") }
    catch { check(error.localizedDescription.contains("fixture pane missing"), "Herdr reports stderr API error") }
    try mode("bad")
    do { _ = try await service.agents(session: "test"); check(false, "Herdr validates success envelope") }
    catch { check(true, "Herdr validates success envelope") }
    try mode("large")
    do { _ = try await service.read(session: "test", pane: "w1:p1"); check(false, "Herdr output is bounded") }
    catch { check(error.localizedDescription.contains("size limit"), "Herdr output is bounded") }
    try mode("timeout")
    let fast = HerdrService(executableOverride: executable, timeout: 0.15)
    let start = Date()
    do { _ = try await fast.sessions(); check(false, "Herdr command timeout") }
    catch { check(Date().timeIntervalSince(start) < 2 && error.localizedDescription.contains("time"), "Herdr timeout completes without indefinite pipe wait") }
    let cancellation = Task { try await service.sessions() }
    try await Task.sleep(nanoseconds: 50_000_000)
    cancellation.cancel()
    do { _ = try await cancellation.value; check(false, "Herdr cancellation") }
    catch { check(error is CancellationError, "Herdr cancellation resumes awaiting caller") }
    let before = try calls().count
    do { _ = try await service.agents(session: "../invalid"); check(false, "Herdr invalid session") }
    catch { check(try calls().count == before, "Herdr invalid session rejected before CLI launch") }
}
