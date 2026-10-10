import Foundation
import Darwin

/// Finds user-installed CLIs without running login shells or reading authentication files.
enum ProviderTools {
    struct Status {
        let provider: String
        let executable: URL?
        let version: String?
        let issue: String?
    }

    static func resolve(provider: String, environment: [String: String] = ProcessInfo.processInfo.environment, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        guard let name = ["Codex": "codex", "Claude": "claude"][provider] else { return nil }
        return searchPaths(environment: environment, home: home).map { URL(fileURLWithPath: $0).appendingPathComponent(name) }.first {
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0.path, isDirectory: &directory) && !directory.boolValue && FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    static func searchPaths(environment: [String: String], home: URL) -> [String] {
        var paths = (environment["PATH"] ?? "").components(separatedBy: ":").filter { $0.hasPrefix("/") }
        paths += ["/opt/homebrew/bin", "/usr/local/bin", home.appendingPathComponent(".local/bin").path, home.appendingPathComponent(".volta/bin").path, home.appendingPathComponent(".npm-global/bin").path, home.appendingPathComponent(".asdf/shims").path]
        let nvm = environment["NVM_DIR"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil } ?? home.appendingPathComponent(".nvm")
        let fnm = environment["FNM_DIR"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil } ?? home.appendingPathComponent("Library/Application Support/fnm")
        for (root, suffix) in [(nvm.appendingPathComponent("versions/node"), "bin"), (fnm.appendingPathComponent("node-versions"), "installation/bin")] {
            // A single directory listing only, never a recursive scan of the home directory.
            let versions = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            paths += versions.filter { $0.lastPathComponent.first == "v" }.sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }.prefix(32).map { $0.appendingPathComponent(suffix).path }
        }
        paths += ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    static func environment(for executable: URL, environment: [String: String] = ProcessInfo.processInfo.environment, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String: String] {
        var result = environment
        // npm wrappers use /usr/bin/env node; include their sibling runtime even in a GUI launch.
        let parent = executable.deletingLastPathComponent().path
        result["PATH"] = ([parent] + searchPaths(environment: environment, home: home).filter { $0 != parent }).joined(separator: ":")
        return result
    }

    static func inspect(provider: String, executableOverride: URL? = nil, timeout: TimeInterval = 4) async -> Status {
        guard let executable = executableOverride ?? resolve(provider: provider) else {
            return Status(provider: provider, executable: nil, version: nil, issue: "CLI not found. Install the official CLI and sign in from Terminal.")
        }
        return await withCheckedContinuation { continuation in
            let probe = VersionProbe(executable: executable, timeout: timeout) { version, issue in
                continuation.resume(returning: Status(provider: provider, executable: executable, version: version, issue: issue))
            }
            probe.start()
        }
    }
}

private final class VersionProbe {
    private let process = Process()
    private let pipe = Pipe()
    private let lock = NSLock()
    private var output = Data()
    private var completed = false
    private var reachedEOF = false
    private var exitStatus: Int32?
    private let completion: (String?, String?) -> Void
    private let timeout: TimeInterval

    init(executable: URL, timeout: TimeInterval, completion: @escaping (String?, String?) -> Void) {
        self.completion = completion
        self.timeout = timeout
        process.executableURL = executable
        process.arguments = ["--version"]
        process.environment = ProviderTools.environment(for: executable)
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
    }

    func start() {
        pipe.fileHandleForReading.readabilityHandler = { [self] handle in
            let data = handle.availableData
            lock.lock()
            if data.isEmpty { reachedEOF = true }
            output.append(data.prefix(max(0, 8192 - output.count)))
            lock.unlock()
            finishIfExited()
        }
        process.terminationHandler = { [self] process in
            lock.lock(); exitStatus = process.terminationStatus; lock.unlock()
            finishIfExited()
        }
        do { try process.run() }
        catch { finish(issue: error.localizedDescription); return }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in
            lock.lock(); let active = !completed; lock.unlock()
            guard active else { return }
            finish(issue: "Version check timed out.")
            if process.isRunning {
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [process] in
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
    }

    private func finishIfExited() {
        lock.lock(); let status = exitStatus; let eof = reachedEOF; lock.unlock()
        guard let status, eof else { return }
        finish(issue: status == 0 ? nil : "Version check exited with status \(status).")
    }

    private func finish(issue: String?) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let data = output
        lock.unlock()
        pipe.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        completion(text.isEmpty ? nil : String(text.prefix(200)), issue ?? (text.isEmpty ? "CLI returned no version." : nil))
    }
}
