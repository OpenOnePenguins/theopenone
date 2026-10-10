import Foundation
import Darwin

struct AgentConnectionStatus {
    enum State: String { case missing, needsSignIn, ready, failed }
    let provider: String
    let state: State
    let executable: URL?
    let detail: String
}

/// Reads only the official CLI's version and authentication status. Raw auth
/// output (which may contain account details) is never shown or persisted.
enum OnboardingProbe {
    static func inspect(provider: String, executable: URL?, timeout: TimeInterval = 8) async -> AgentConnectionStatus {
        func result(_ state: AgentConnectionStatus.State, _ detail: String) -> AgentConnectionStatus {
            AgentConnectionStatus(provider: provider, state: state, executable: executable, detail: detail)
        }
        guard let executable else { return result(.missing, "Install the official CLI to connect this agent.") }
        let version = await command(executable, ["--version"], timeout: timeout)
        guard version.code == 0, !version.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return result(.failed, "Couldn’t run this CLI. Check its installation, then try again.")
        }
        let args = provider == "Claude" ? ["auth", "status", "--json"] : ["login", "status"]
        let auth = await command(executable, args, timeout: timeout)
        if auth.timedOut { return result(.failed, "The sign-in check timed out. Try again.") }
        if provider == "Claude" {
            guard let object = try? JSONSerialization.jsonObject(with: Data(auth.output.utf8)) as? [String: Any], let loggedIn = object["loggedIn"] as? Bool else {
                return result(.failed, "Couldn’t confirm sign-in. Update Claude Code, sign in, and check again.")
            }
            return loggedIn && auth.code == 0 ? result(.ready, "Installed and signed in.") : result(.needsSignIn, "Sign in with your existing Claude account.")
        }
        let output = auth.output.lowercased()
        if output.contains("not logged in") || output.contains("not authenticated") { return result(.needsSignIn, "Sign in with your existing Codex account.") }
        if auth.code == 0 && output.contains("logged in") { return result(.ready, "Installed and signed in.") }
        return result(.failed, "Couldn’t confirm sign-in. Update Codex, sign in, and check again.")
    }

    struct Output { let code: Int32; let output: String; let timedOut: Bool }
    static func command(_ executable: URL, _ arguments: [String], timeout: TimeInterval) async -> Output {
        await withCheckedContinuation { continuation in
            BoundedSetupProcess(executable: executable, arguments: arguments, timeout: timeout) { continuation.resume(returning: $0) }.start()
        }
    }

    static func loginScript(provider: String, executable: URL) -> String {
        func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let path = ProviderTools.environment(for: executable)["PATH"] ?? "/usr/bin:/bin"
        let args = provider == "Claude" ? "auth login" : "login"
        return "#!/bin/zsh\nexport PATH=\(quote(path))\n\(quote(executable.path)) \(args)\nprintf '\\nReturn to Open One and click Check again.\\n'\n"
    }
}

private final class BoundedSetupProcess {
    private let process = Process()
    private let pipe = Pipe()
    private let lock = NSLock()
    private var bytes = Data()
    private var finished = false
    private let timeout: TimeInterval
    private let completion: (OnboardingProbe.Output) -> Void
    init(executable: URL, arguments: [String], timeout: TimeInterval, completion: @escaping (OnboardingProbe.Output) -> Void) {
        self.timeout = timeout; self.completion = completion
        process.executableURL = executable; process.arguments = arguments
        process.environment = ProviderTools.environment(for: executable)
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe; process.standardError = pipe
    }
    func start() {
        let fd = pipe.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        pipe.fileHandleForReading.readabilityHandler = { [self] _ in drain() }
        process.terminationHandler = { [self] process in
            // Drain bytes after exit without waiting for descendants holding stdout.
            pipe.fileHandleForReading.readabilityHandler = nil
            drain()
            finish(code: process.terminationStatus, timedOut: false)
        }
        do { try process.run() } catch { finish(code: -1, timedOut: false); return }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in
            lock.lock(); let active = !finished; lock.unlock()
            guard active else { return }
            finish(code: -1, timedOut: true)
            if process.isRunning {
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [process] in if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
            }
        }
    }
    private func drain() {
        // Serialize reading and appending so exit cannot overtake an in-flight read.
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        var buffer = [UInt8](repeating: 0, count: 4096)
        for _ in 0..<16 {
            let count = read(pipe.fileHandleForReading.fileDescriptor, &buffer, buffer.count)
            if count <= 0 { break }
            bytes.append(contentsOf: buffer.prefix(min(count, max(0, 16384 - bytes.count))))
        }
    }
    private func finish(code: Int32, timedOut: Bool) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true; let text = String(decoding: bytes, as: UTF8.self); lock.unlock()
        pipe.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        completion(.init(code: code, output: text, timedOut: timedOut))
    }
}
