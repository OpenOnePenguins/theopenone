import Foundation
import Darwin
import OneCore

/// Optional adapter to the public CLI. Every live request names its session and pane.
final class HerdrService {
    private let executableOverride: URL?
    private let timeout: TimeInterval
    init(executableOverride: URL? = nil, timeout: TimeInterval = 8) {
        self.executableOverride = executableOverride; self.timeout = max(0.05, timeout)
    }
    func sessions() async throws -> [HerdrSession] {
        struct Sessions: Decodable { let sessions: [HerdrSession] }
        return try JSONDecoder().decode(Sessions.self, from: await run(["session", "list", "--json"])).sessions
    }
    func agents(session: String) async throws -> [HerdrAgent] {
        let result = try await result(session: session, arguments: ["agent", "list"], type: "agent_list")
        guard let agents = result["agents"] else { throw HerdrError.invalidResponse }
        return try JSONDecoder().decode([HerdrAgent].self, from: JSONSerialization.data(withJSONObject: agents))
    }
    func get(session: String, pane: String) async throws -> HerdrAgent {
        try validatePane(pane)
        return try decodeAgent(await result(session: session, arguments: ["agent", "get", pane], type: "agent_info"))
    }
    func read(session: String, pane: String) async throws -> String {
        try validatePane(pane)
        return String(decoding: try await run(prefix(session) + ["agent", "read", pane, "--source", "recent-unwrapped", "--lines", "120"]), as: UTF8.self)
    }
    func prompt(session: String, pane: String, terminalID: String, text: String, expectedIdentity: String? = nil) async throws -> HerdrAgent {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw HerdrError.failed("Enter a message first.") }
        let current = try await get(session: session, pane: pane)
        guard current.terminalID == terminalID, expectedIdentity == nil || current.identityFingerprint == expectedIdentity else { throw HerdrError.replaced }
        guard current.agentStatus != "blocked" else { throw HerdrError.failed("This agent needs an approval in its terminal before it can receive a task.") }
        guard current.agentStatus == "idle" || current.agentStatus == "done" else { throw HerdrError.failed("This agent is not ready for another task.") }
        try Task.checkCancellation()
        // Herdr scans global selectors anywhere before `--`, while agent prompt has no
        // end-of-options positional form. Whitespace keeps a flag-looking draft literal.
        let literalText = text.hasPrefix("-") ? "\n" + text : text
        return try decodeAgent(await result(session: session, arguments: ["agent", "prompt", pane, literalText], type: "agent_prompted"))
    }
    func interrupt(session: String, pane: String, terminalID: String, expectedIdentity: String? = nil) async throws {
        let current = try await get(session: session, pane: pane)
        guard current.terminalID == terminalID, expectedIdentity == nil || current.identityFingerprint == expectedIdentity else { throw HerdrError.replaced }
        guard current.agentStatus == "working" else { throw HerdrError.failed("Only a working agent can be interrupted.") }
        try Task.checkCancellation()
        _ = try await result(session: session, arguments: ["agent", "send-keys", pane, "esc"], type: "ok")
    }
    func sendKey(session: String, pane: String, terminalID: String, key: String, expectedIdentity: String? = nil) async throws {
        guard ["up", "down", "enter", "esc"].contains(key) else { throw HerdrError.failed("Unsupported approval control.") }
        let current = try await get(session: session, pane: pane)
        guard current.terminalID == terminalID, expectedIdentity == nil || current.identityFingerprint == expectedIdentity else { throw HerdrError.replaced }
        guard current.agentStatus == "blocked" else { throw HerdrError.failed("This agent is no longer waiting at a question or approval dialog. Refresh its terminal output.") }
        try Task.checkCancellation()
        _ = try await result(session: session, arguments: ["agent", "send-keys", pane, key], type: "ok")
    }
    private func prefix(_ session: String) throws -> [String] {
        guard !session.isEmpty, session.utf8.count <= 64, session != ".", session != "..", session.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains($0) }) else { throw HerdrError.failed("Choose a valid Herdr session.") }
        return ["--session", session]
    }
    private func validatePane(_ pane: String) throws {
        guard !pane.isEmpty, !pane.hasPrefix("-"), pane.utf8.count <= 256, !pane.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw HerdrError.failed("Invalid Herdr pane reference.") }
    }
    private func decodeAgent(_ result: [String: Any]) throws -> HerdrAgent {
        guard let agent = result["agent"] else { throw HerdrError.invalidResponse }
        return try JSONDecoder().decode(HerdrAgent.self, from: JSONSerialization.data(withJSONObject: agent))
    }
    private func result(session: String, arguments: [String], type: String) async throws -> [String: Any] {
        let data = try await run(prefix(session) + arguments)
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw HerdrError.invalidResponse }
        if let error = envelope["error"] as? [String: Any] { throw HerdrError.failed(error["message"] as? String ?? "Herdr rejected this request.") }
        guard let result = envelope["result"] as? [String: Any], result["type"] as? String == type else { throw HerdrError.invalidResponse }
        return result
    }
    private func run(_ arguments: [String]) async throws -> Data {
        let executable = executableOverride ?? ProviderTools.searchPaths(environment: ProcessInfo.processInfo.environment, home: FileManager.default.homeDirectoryForCurrentUser).map { URL(fileURLWithPath: $0).appendingPathComponent("herdr") }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
        guard let executable else { throw HerdrError.failed("Herdr CLI not found. Install Herdr to connect its running sessions.") }
        let command = HerdrCommand(executable: executable, arguments: arguments, timeout: timeout)
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { command.start($0) }
        }, onCancel: { command.cancel() })
    }
}

enum HerdrError: LocalizedError {
    case failed(String), invalidResponse, replaced, timeout, tooLarge
    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        case .invalidResponse: return "Herdr returned an unexpected response."
        case .replaced: return "The agent in this pane changed. Refresh before trying again."
        case .timeout: return "Herdr did not respond in time. Check the terminal before retrying; the action may have been delivered."
        case .tooLarge: return "Herdr output exceeded the size limit."
        }
    }
}

private final class HerdrCommand {
    private let process = Process(), output = Pipe(), errors = Pipe(), lock = NSLock()
    private let timeout: TimeInterval
    private var stdout = Data(), stderr = Data()
    private var outputClosed = false, errorsClosed = false, cancelled = false, completed = false
    private var status: Int32?
    private var continuation: CheckedContinuation<Data, Error>?
    init(executable: URL, arguments: [String], timeout: TimeInterval) {
        self.timeout = timeout
        process.executableURL = executable; process.arguments = arguments
        process.environment = ProviderTools.environment(for: executable)
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice; process.standardOutput = output; process.standardError = errors
    }
    func start(_ continuation: CheckedContinuation<Data, Error>) {
        lock.lock()
        self.continuation = continuation
        if cancelled { lock.unlock(); finish(.failure(CancellationError())); return }
        output.fileHandleForReading.readabilityHandler = { [self] handle in receive(handle.availableData, error: false) }
        errors.fileHandleForReading.readabilityHandler = { [self] handle in receive(handle.availableData, error: true) }
        process.terminationHandler = { [self] process in
            lock.lock(); status = process.terminationStatus; lock.unlock(); settle()
        }
        do { try process.run(); lock.unlock() }
        catch { lock.unlock(); finish(.failure(error)); return }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in finish(.failure(HerdrError.timeout)) }
    }
    func cancel() {
        lock.lock(); cancelled = true; let started = continuation != nil; lock.unlock()
        if started { finish(.failure(CancellationError())) }
    }
    private func receive(_ data: Data, error: Bool) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        let limit = error ? 65_536 : 1_048_576
        let size = error ? stderr.count : stdout.count
        let exceeded = size + data.count > limit
        if error { stderr.append(data.prefix(max(0, limit - size))); if data.isEmpty { errorsClosed = true } }
        else { stdout.append(data.prefix(max(0, limit - size))); if data.isEmpty { outputClosed = true } }
        lock.unlock()
        if exceeded { finish(.failure(HerdrError.tooLarge)) } else { settle() }
    }
    private func settle() {
        lock.lock()
        guard let status, outputClosed, errorsClosed, !completed else { lock.unlock(); return }
        let data = stdout, failure = stderr
        lock.unlock()
        if status == 0 { finish(.success(data)) }
        else {
            let envelope = (try? JSONSerialization.jsonObject(with: failure)) as? [String: Any]
            let message = (envelope?["error"] as? [String: Any])?["message"] as? String
            finish(.failure(HerdrError.failed(message ?? String(decoding: failure.suffix(1500), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Herdr exited with status \(status).")))
        }
    }
    private func finish(_ result: Result<Data, Error>) {
        lock.lock()
        guard !completed, let continuation else { lock.unlock(); return }
        completed = true; self.continuation = nil
        lock.unlock()
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        if process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [process] in
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        continuation.resume(with: result)
    }
}

private extension String { var nonEmpty: String? { isEmpty ? nil : self } }
