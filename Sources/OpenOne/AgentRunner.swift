import Foundation
import AppKit
import Darwin
import OneCore

enum RunnerUpdate {
    case session(String), text(String), activity(String), finished(Int32), error(String), writerBusy
    case approval(AgentApproval), approvalResolved(String)
}

struct AgentApproval: Identifiable, Equatable {
    let id: String
    let title: String
    let details: String
    let allowEnabled: Bool
}

/// Runs new, resumed, or explicitly forked sessions using the provider's native IDs.
final class AgentRunner {
    private var process: Process?
    private let processLock = NSLock()
    private var cancelled = false
    private let executableOverride: URL?
    private let useApprovalTransport: Bool
    private var approvalDirectory: URL?
    private var approvalRequests: [String: AgentApproval] = [:]
    private let queue = DispatchQueue(label: "openone.agent.\(UUID().uuidString)")

    // Existing one-way fixture CLIs remain available to legacy transport tests.
    // Production always uses the bidirectional transport; its own fixtures opt in.
    init(executableOverride: URL? = nil, useApprovalTransport: Bool? = nil) {
        self.executableOverride = executableOverride
        self.useApprovalTransport = useApprovalTransport ?? (executableOverride == nil)
    }

    func respondToApproval(_ id: String, allow: Bool) throws {
        processLock.lock(); defer { processLock.unlock() }
        guard !cancelled, process?.isRunning == true, let directory = approvalDirectory,
              let request = approvalRequests[id], !allow || request.allowEnabled else {
            throw QueueDeliveryError.message("This approval is no longer available. Review the agent's latest request.")
        }
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "allow": allow])
        try data.write(to: directory.appendingPathComponent(id + ".json"), options: .atomic)
        approvalRequests.removeValue(forKey: id)
    }

    static let writerBusyMessage = "Message not sent: Codex opened this conversation elsewhere while sending. Your draft is saved. Retry to queue it in the existing conversation."

    static func queueArguments(agent: Agent, prompt: String, image: URL?) throws -> [String] {
        guard agent.provider == "Codex", let session = agent.sessionID, UUID(uuidString: session) != nil else { throw RunnerError.invalidSession }
        var args = ["queue", "--thread", session, "--message=" + prompt]
        if let image { args += ["--image", image.path] }
        return args
    }

    /// Queue through Codex's native durable input queue. This never resumes the
    /// thread or takes its writer lock, including for embedded (--no-daemon) TUIs.
    func enqueue(agent: Agent, prompt: String, image: URL?, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async { [self] in
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("open-one-queue-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: temporary) }
            do {
                guard let executable = executableOverride ?? ProviderTools.resolve(provider: "Codex") else {
                    throw QueueDeliveryError.message("Install the Codex CLI to send to this conversation.")
                }
                let process = Process()
                process.executableURL = executable
                process.arguments = try Self.queueArguments(agent: agent, prompt: prompt, image: image)
                if let image { try Self.validateImage(image) }
                process.currentDirectoryURL = URL(fileURLWithPath: NSString(string: agent.directory).expandingTildeInPath)
                process.environment = ProviderTools.environment(for: executable)
                if let home = agent.providerHome { process.environment?["CODEX_HOME"] = home }
                process.standardInput = FileHandle.nullDevice
                try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                let stdout = temporary.appendingPathComponent("stdout"), stderr = temporary.appendingPathComponent("stderr")
                for url in [stdout, stderr] {
                    guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
                }
                let output = try FileHandle(forWritingTo: stdout), errors = try FileHandle(forWritingTo: stderr)
                defer { try? output.close(); try? errors.close() }
                process.standardOutput = output; process.standardError = errors
                let exited = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in exited.signal() }
                processLock.lock()
                if cancelled { processLock.unlock(); throw QueueDeliveryError.message("Sending was cancelled. Check Codex's queue before retrying.") }
                self.process = process
                do { try process.run(); processLock.unlock() }
                catch { self.process = nil; processLock.unlock(); throw error }
                let timedOut = exited.wait(timeout: .now() + 30) == .timedOut
                if timedOut { stop() }
                process.waitUntilExit()
                processLock.lock(); self.process = nil; let stopped = cancelled; processLock.unlock()
                func tail(_ url: URL) throws -> String {
                    let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
                    let length = try file.seekToEnd(); try file.seek(toOffset: length > 65536 ? length - 65536 : 0)
                    return String(decoding: try file.readToEnd() ?? Data(), as: UTF8.self)
                }
                let receipt = try tail(stdout)
                // Exit success alone is not proof that this exact thread accepted it.
                let suffix = " for thread \(agent.sessionID!)."
                if process.terminationStatus == 0, let line = receipt.components(separatedBy: .newlines).first(where: {
                    $0.hasPrefix("Queued message ") && $0.hasSuffix(suffix)
                        && UUID(uuidString: String($0.dropFirst(15).dropLast(suffix.count))) != nil
                }) { completion(.success(line)); return }
                if timedOut || stopped { throw QueueDeliveryError.message("Codex did not confirm delivery. Your draft is saved; check its terminal queue before retrying to avoid sending twice.") }
                let detail = try tail(stderr).trimmingCharacters(in: .whitespacesAndNewlines)
                throw QueueDeliveryError.message("Codex could not confirm the queued message. Your draft is saved. " + (detail.isEmpty ? "Check its terminal before retrying." : String(detail.suffix(1800))))
            } catch { completion(.failure(error)) }
        }
    }

    static func isWriterConflict(_ message: String) -> Bool {
        message.contains("active writer") && (message.contains("thread-store conflict") || message.contains("thread/resume failed"))
    }

    /// An existing lock file alone is not evidence of a live writer. Probe the
    /// OS lock without creating, deleting, or retaining a lock file.
    static func hasActiveWriter(_ agent: Agent) throws -> Bool {
        guard agent.provider == "Codex", let session = agent.sessionID else { return false }
        guard !session.isEmpty, !session.contains("/"), session != ".", session != ".." else { throw RunnerError.invalidSession }
        let home = agent.providerHome ?? ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        let file = URL(fileURLWithPath: home).appendingPathComponent("thread-writer-locks").appendingPathComponent(session + ".lock")
        let descriptor = open(file.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            if errno == ENOENT { return false }
            throw RunnerError.writerCheckFailed
        }
        defer { close(descriptor) }
        if flock(descriptor, LOCK_SH | LOCK_NB) == 0 {
            _ = flock(descriptor, LOCK_UN)
            return false
        }
        if errno == EWOULDBLOCK || errno == EAGAIN { return true }
        throw RunnerError.writerCheckFailed
    }

    static func arguments(agent: Agent, prompt: String, image: URL?) throws -> [String] {
        guard ["Codex", "Claude"].contains(agent.provider) else { throw RunnerError.unsupportedProvider }
        let program = agent.provider == "Claude" ? "claude" : "codex"
        for reference in [agent.sessionID, agent.forkSessionID].compactMap({ $0 }) {
            guard !reference.isEmpty, !reference.hasPrefix("-") else { throw RunnerError.invalidSession }
        }
        if program == "codex" {
            var args = ["exec"]
            if let session = agent.sessionID { args += ["resume", session] }
            else if let source = agent.forkSessionID { args += ["fork", source] }
            args += ["--json"]
            if let image { args += ["--image", image.path] }
            return args + ["--", prompt]
        }
        var args = ["-p", "--verbose", "--output-format", "stream-json"]
        if let session = agent.sessionID { args += ["--resume", session] }
        else if let source = agent.forkSessionID { args += ["--resume", source, "--fork-session"] }
        return image == nil ? args + ["--", prompt] : args + ["--input-format", "stream-json"]
    }

    static func validateImage(_ image: URL, provider: String = "Codex") throws {
        guard let data = try? Data(contentsOf: image), NSBitmapImageRep(data: data) != nil else { throw RunnerError.invalidImage }
        if provider == "Claude" { _ = try imageInput(prompt: "", image: image) }
    }

    static func imageInput(prompt: String, image: URL) throws -> Data {
        guard let data = try? Data(contentsOf: image), let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:]) else { throw RunnerError.invalidImage }
        guard png.count <= 5 * 1024 * 1024 else { throw RunnerError.imageTooLarge }
        let message: [String: Any] = ["type": "user", "parent_tool_use_id": NSNull(), "message": ["role": "user", "content": [
            ["type": "text", "text": prompt],
            ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": png.base64EncodedString()]]
        ]]]
        return try JSONSerialization.data(withJSONObject: message) + Data([10])
    }

    func start(agent: Agent, prompt: String, image: URL?, update: @escaping (RunnerUpdate) -> Void) {
        queue.async { [self] in
            let process = Process()
            let program = agent.provider == "Claude" ? "claude" : "codex"
            guard let executable = executableOverride ?? ProviderTools.resolve(provider: agent.provider) else {
                update(.error("\(program) is not installed. Install and sign in to its official CLI, then retry.")); update(.finished(1)); return
            }
            process.executableURL = executable
            let directory = NSString(string: agent.directory).expandingTildeInPath
            var isDirectory: ObjCBool = false
            guard directory.hasPrefix("/"), FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
                update(.error("The project folder no longer exists. Choose an existing folder for a new session.")); update(.finished(1)); return
            }
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
            do { process.arguments = try Self.arguments(agent: agent, prompt: prompt, image: image) }
            catch { update(.error(error.localizedDescription)); update(.finished(1)); return }
            do {
                if try Self.hasActiveWriter(agent) { update(.writerBusy); update(.finished(1)); return }
            } catch { update(.error(error.localizedDescription)); update(.finished(1)); return }
            process.environment = ProviderTools.environment(for: executable)
            if agent.provider == "Codex", let home = agent.providerHome {
                process.environment?["CODEX_HOME"] = home
            }
            process.standardInput = FileHandle.nullDevice
            // Use a private file as stdin so a large image cannot deadlock against
            // the child's stdout. Never place base64 image contents in argv.
            var inputURL: URL?
            var inputHandle: FileHandle?
            var approvalRoot: URL?
            defer {
                try? inputHandle?.close()
                if let inputURL { try? FileManager.default.removeItem(at: inputURL) }
                processLock.lock(); approvalDirectory = nil; approvalRequests = [:]; processLock.unlock()
                if let approvalRoot { try? FileManager.default.removeItem(at: approvalRoot) }
            }
            do {
                if useApprovalTransport {
                    let bundled = Bundle.main.url(forResource: "one-agent", withExtension: "py")
                    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("scripts/one-agent.py")
                    guard let script = bundled ?? (FileManager.default.fileExists(atPath: source.path) ? source : nil) else {
                        throw QueueDeliveryError.message("The agent approval helper is missing. Rebuild Open One before sending.")
                    }
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("open-one-agent-\(UUID().uuidString)")
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                    approvalRoot = folder
                    var config: [String: Any] = ["provider": agent.provider, "executable": executable.path, "directory": directory, "prompt": prompt]
                    config["sessionID"] = agent.sessionID; config["forkSessionID"] = agent.forkSessionID
                    if let image { try Self.validateImage(image, provider: agent.provider); config["image"] = image.path }
                    if program == "claude" {
                        if let image { config["claudeInput"] = try JSONSerialization.jsonObject(with: Self.imageInput(prompt: prompt, image: image)) }
                        else { config["claudeInput"] = ["type": "user", "parent_tool_use_id": NSNull(), "message": ["role": "user", "content": [["type": "text", "text": prompt]]]] }
                    }
                    guard FileManager.default.createFile(atPath: folder.appendingPathComponent("config.json").path,
                          contents: try JSONSerialization.data(withJSONObject: config), attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments = ["python3", script.path, folder.path]
                    processLock.lock(); approvalDirectory = folder; processLock.unlock()
                } else if let image {
                    try Self.validateImage(image)
                    if program == "claude" {
                        let data = try Self.imageInput(prompt: prompt, image: image)
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent("open-one-image-\(UUID().uuidString).jsonl")
                        inputURL = url
                        guard FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw RunnerError.invalidImage }
                        inputHandle = try FileHandle(forReadingFrom: url)
                        process.standardInput = inputHandle
                    }
                }
            } catch { update(.error(error.localizedDescription)); update(.finished(1)); return }
            let output = Pipe(), errors = Pipe()
            process.standardOutput = output; process.standardError = errors
            let errorBuffer = LockedData()
            errors.fileHandleForReading.readabilityHandler = { handle in errorBuffer.append(handle.availableData) }
            defer {
                errors.fileHandleForReading.readabilityHandler = nil
                processLock.lock(); self.process = nil; processLock.unlock()
            }
            processLock.lock()
            if cancelled { processLock.unlock(); update(.finished(130)); return }
            self.process = process
            do { try process.run(); processLock.unlock() }
            catch { processLock.unlock(); update(.error(error.localizedDescription)); update(.finished(1)); return }
            var reportedError = false
            var rejectedSession = false
            var sessionAccepted = false
            let report: (RunnerUpdate) -> Void = { [self] item in
                guard !rejectedSession else { return }
                if case .session(let received) = item, let expected = agent.sessionID, received != expected {
                    rejectedSession = true; reportedError = true
                    update(.error("The CLI opened a different session instead of resuming this conversation. Stopped to preserve its original identity."))
                    self.stop(); return
                }
                if case .error(let message) = item {
                    reportedError = true
                    if !sessionAccepted, agent.provider == "Codex", agent.sessionID != nil, Self.isWriterConflict(message) { update(.writerBusy); return }
                }
                switch item {
                case .session, .text, .activity: sessionAccepted = true
                case .approval(let request):
                    processLock.lock(); approvalRequests[request.id] = request; processLock.unlock()
                case .approvalResolved(let id):
                    processLock.lock(); approvalRequests.removeValue(forKey: id); processLock.unlock()
                default: break
                }
                update(item)
            }
            var buffer = Data()
            let descriptor = output.fileHandleForReading.fileDescriptor
            var bytes = [UInt8](repeating: 0, count: 65536)
            while true {
                var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
                let ready = poll(&pollDescriptor, 1, 200)
                if ready < 0 { if errno == EINTR { continue }; break }
                if ready == 0 {
                    // Tool subprocesses can inherit stdout after the CLI has exited.
                    if !process.isRunning { break }
                    continue
                }
                let count = read(descriptor, &bytes, bytes.count)
                if count == 0 { break }
                if count < 0 { if errno == EINTR { continue }; break }
                buffer.append(contentsOf: bytes.prefix(count))
                // Bound malformed/unterminated output rather than retaining it indefinitely.
                if buffer.count > 8_388_608 {
                    report(.error("The CLI returned an oversized output event. The session was stopped."))
                    stop()
                    buffer.removeAll()
                    break
                }
                while let newline = buffer.firstIndex(of: 10) {
                    let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
                    Self.parse(line, update: report)
                }
            }
            if !buffer.isEmpty { Self.parse(buffer, update: report) }
            process.waitUntilExit()
            errors.fileHandleForReading.readabilityHandler = nil
            if process.terminationStatus != 0, let message = String(data: errorBuffer.data, encoding: .utf8), !message.isEmpty {
                report(.error(String(message.suffix(6000))))
            }
            processLock.lock(); let stopped = cancelled; processLock.unlock()
            update(.finished(stopped ? 130 : (reportedError && process.terminationStatus == 0 ? 1 : process.terminationStatus)))
        }
    }

    static func parse(_ data: Data, update: (RunnerUpdate) -> Void) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let type = object["type"] as? String ?? ""
        if type == "openone.approval", let id = object["id"] as? String, UUID(uuidString: id) != nil,
           let title = object["title"] as? String, let details = object["details"] as? String,
           let enabled = object["allowEnabled"] as? Bool {
            update(.approval(AgentApproval(id: id, title: title, details: details, allowEnabled: enabled)))
            return
        }
        if type == "openone.approvalResolved", let id = object["id"] as? String {
            update(.approvalResolved(id)); return
        }
        if let session = object["thread_id"] as? String ?? object["session_id"] as? String { update(.session(session)) }
        if type == "item.completed", let item = object["item"] as? [String: Any] {
            if item["type"] as? String == "agent_message", let text = item["text"] as? String { update(.text(text)) }
            else if let command = item["command"] as? String { update(.activity(command)) }
        }
        if type == "assistant", let message = object["message"] as? [String: Any], let blocks = message["content"] as? [[String: Any]] {
            for block in blocks {
                if let text = block["text"] as? String { update(.text(text)) }
                if block["type"] as? String == "tool_use", let name = block["name"] as? String { update(.activity(name)) }
            }
        }
        if type == "error" || type == "turn.failed" {
            let nested = object["error"] as? [String: Any]
            update(.error(object["message"] as? String ?? nested?["message"] as? String ?? "The agent turn failed."))
        }
        if type == "result", object["is_error"] as? Bool == true {
            update(.error(object["result"] as? String ?? (object["errors"] as? [String])?.joined(separator: "\n") ?? "The agent reported an error."))
        }
    }

    func stop() {
        processLock.lock(); defer { processLock.unlock() }
        cancelled = true
        if let process, process.isRunning {
            process.terminate()
            // Escalate only this still-running Process, never another terminal session.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }
}

enum RunnerError: LocalizedError {
    case invalidSession, unsupportedImage, unsupportedProvider, invalidImage, imageTooLarge, writerCheckFailed
    var errorDescription: String? {
        switch self {
        case .unsupportedProvider: return "Choose Codex or Claude to start a managed session."
        case .invalidSession: return "The agent supplied an invalid session reference. Start a new conversation instead."
        case .unsupportedImage: return "Image attachments require a Codex session. Remove the attachment or choose Codex."
        case .invalidImage: return "The attached image is missing or unreadable. Attach it again before sending."
        case .imageTooLarge: return "This image exceeds Claude's 5 MB limit. Capture a smaller region before sending."
        case .writerCheckFailed: return "Could not check this conversation's Codex home. Check access to its files, then retry. Your draft is saved."
        }
    }
}

private enum QueueDeliveryError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

private final class LockedData {
    private let lock = NSLock()
    private var storage = Data()
    var data: Data { lock.lock(); defer { lock.unlock() }; return storage }
    func append(_ data: Data) { lock.lock(); defer { lock.unlock() }; storage.append(data); if storage.count > 65536 { storage = storage.suffix(65536) } }
}
