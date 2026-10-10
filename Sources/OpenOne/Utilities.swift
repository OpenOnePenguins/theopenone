import AppKit
import Combine
import OneCore
import Darwin

struct QuotaWindow: Codable, Identifiable {
    var id: String
    var label: String
    var bucket: String
    var used: Double
    var resetsAt: Double?
    var plan: String?
    var remaining: Double { max(0, 100 - used) }
}
struct ProviderQuota: Codable {
    var provider: String
    var capturedAt: Double
    var windows: [QuotaWindow]
}

@MainActor final class Utilities: ObservableObject {
    let root: URL
    @Published var notes = ""
    @Published var notesSaved = true
    @Published var error: String?
    @Published var includeNotes = true
    @Published var feedback = ""
    @Published var feedbackDestination = ""
    @Published var quotas: [ProviderQuota] = []
    @Published var refreshingUsage = false
    @Published var usageError: String?
    @Published var claudeSetupMessage: String?
    @Published var configuringClaude = false
    @Published var remoteRunning = false
    @Published var remoteStarting = false
    @Published var remoteListenHost = "127.0.0.1"
    @Published var remoteConversationCount = 0
    @Published var remoteURL: URL?
    @Published var remotePort = 0
    @Published var remoteError: String?
    private var notesTask: Task<Void, Never>?
    private var remoteProcess: Process?
    private var usageTask: Task<Void, Never>?
    private var writable = true

    init(root: URL) {
        self.root = root
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("notes.md").path) {
                notes = try String(contentsOf: root.appendingPathComponent("notes.md"), encoding: .utf8)
            }
        } catch { self.error = "Could not read notes. The saved file has been left untouched."; writable = false }
        if let data = try? Data(contentsOf: root.appendingPathComponent("utility-settings.json")), let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            includeNotes = settings["includeNotes"] as? Bool ?? true
            feedbackDestination = settings["feedbackDestination"] as? String ?? ""
        }
        feedback = (try? String(contentsOf: root.appendingPathComponent("feedback-draft.md"), encoding: .utf8)) ?? ""
        loadClaudeUsage()
    }
    func updateNotes(_ value: String) {
        notes = value; notesSaved = false; notesTask?.cancel()
        notesTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }; self?.saveNotes()
        }
    }
    func saveNotes() {
        guard writable else { return }
        do { try privateWrite(Data(notes.utf8), name: "notes.md"); notesSaved = true; error = nil }
        catch { self.error = "Notes could not be saved: \(error.localizedDescription)"; notesSaved = false }
    }
    func promptWithNotes(_ prompt: String) -> String {
        guard includeNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return prompt }
        return "Working memory provided by the user:\n\(String(notes.prefix(16_000)))\n\nCurrent request:\n\(prompt)"
    }
    func saveSettings() {
        do {
            let data = try JSONSerialization.data(withJSONObject: ["includeNotes": includeNotes, "feedbackDestination": feedbackDestination])
            try privateWrite(data, name: "utility-settings.json")
        } catch { self.error = "Could not save preferences: \(error.localizedDescription)" }
    }
    func saveFeedback() {
        do { try privateWrite(Data(feedback.utf8), name: "feedback-draft.md") }
        catch { self.error = "Could not save feedback draft: \(error.localizedDescription)" }
    }
    func feedbackReport() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        return "# Open One feedback\n\n\(feedback)\n\nApp: \(version)\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
    }
    func exportFeedback() {
        let dialog = NSSavePanel(); dialog.nameFieldStringValue = "Open-One-feedback.md"
        if dialog.runModal() == .OK, let url = dialog.url {
            do { try Data(feedbackReport().utf8).write(to: url, options: .atomic) }
            catch { self.error = "Could not export feedback: \(error.localizedDescription)" }
        }
    }
    func openFeedbackDraft() {
        saveFeedback(); saveSettings()
        let destination = feedbackDestination.trimmingCharacters(in: .whitespacesAndNewlines)
        var components: URLComponents?
        if destination.contains("@"), !destination.contains("://"), !destination.contains("\n") {
            components = URLComponents(); components?.scheme = "mailto"; components?.path = destination
            components?.queryItems = [URLQueryItem(name: "subject", value: "Open One feedback"), URLQueryItem(name: "body", value: feedbackReport())]
        } else if let url = URL(string: destination), url.scheme == "https", url.host == "github.com", url.path.hasSuffix("/issues") {
            components = URLComponents(url: url.appendingPathComponent("new"), resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "title", value: "Open One feedback"), URLQueryItem(name: "body", value: feedbackReport())]
        }
        guard let url = components?.url else { error = "Enter an email address or a GitHub repository issues URL."; return }
        NSWorkspace.shared.open(url)
    }
    private func privateWrite(_ data: Data, name: String) throws {
        let url = root.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func loadClaudeUsage() {
        if let data = try? Data(contentsOf: root.appendingPathComponent("claude-usage.json")), let quota = try? JSONDecoder().decode(ProviderQuota.self, from: data) {
            quotas.removeAll { $0.provider == "Claude" }; quotas.append(quota)
        }
    }
    func refreshUsage() {
        guard !refreshingUsage else { return }
        loadClaudeUsage(); refreshingUsage = true; usageError = nil
        guard let executable = ProviderTools.resolve(provider: "Codex"), let script = Bundle.main.url(forResource: "one-usage", withExtension: "py") else {
            usageError = "Install and sign in to Codex to show its quota."; refreshingUsage = false; return
        }
        usageTask = Task { [weak self] in
            let result = await Task.detached { () -> Data? in
                let process = Process(); let output = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["python3", script.path, "codex", "--executable", executable.path]
                process.environment = ProviderTools.environment(for: executable)
                process.standardOutput = output; process.standardError = FileHandle.nullDevice
                do { try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); return data }
                catch { return nil }
            }.value
            guard let self else { return }; self.refreshingUsage = false
            if let result, let quota = try? JSONDecoder().decode(ProviderQuota.self, from: result) {
                self.quotas.removeAll { $0.provider == "Codex" }; self.quotas.append(quota)
            } else {
                let response = result.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                self.usageError = response?["error"] as? String ?? "Could not refresh Codex quota. Check Python and CLI availability."
            }
        }
    }
    func configureClaudeUsage(restore: Bool = false) {
        guard !configuringClaude, let script = Bundle.main.url(forResource: "one-claude-statusline", withExtension: "py") else { return }
        configuringClaude = true
        let path = root.path
        Task { [weak self] in
            let message = await Task.detached { () -> String in
                let process = Process(), output = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["python3", script.path, restore ? "restore" : "install", "--root", path]
                process.standardOutput = output; process.standardError = output
                do {
                    try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                    return String(data: data, encoding: .utf8) ?? "No response from setup."
                } catch { return "Could not run setup: \(error.localizedDescription)" }
            }.value
            self?.configuringClaude = false; self?.claudeSetupMessage = message
        }
    }
    var claudeCaptureCommand: String {
        let script = Bundle.main.url(forResource: "one-usage", withExtension: "py")?.path ?? "one-usage.py"
        return "python3 \(shellQuote(script)) capture-claude --root \(shellQuote(root.path))"
    }
    private func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    var lanAddresses: [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return [] }
        defer { freeifaddrs(interfaces) }
        var found: [(String, String)] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor {
            defer { cursor = item.pointee.ifa_next }
            let value = item.pointee
            guard let address = value.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  value.ifa_flags & UInt32(IFF_UP) != 0, value.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            let name = String(cString: value.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let host = String(cString: buffer)
            let parts = host.split(separator: ".").compactMap { Int($0) }
            guard parts.count == 4, parts[0] == 10 || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 192 && parts[1] == 168) else { continue }
            found.append((name, host))
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }
    func startRemote(lanAddress: String? = nil) {
        guard !remoteRunning, !remoteStarting, remoteProcess == nil else { return }
        guard let script = Bundle.main.url(forResource: "one-remote", withExtension: "py") else { remoteError = "Remote bridge is missing from the app bundle."; return }
        let addresses = lanAddresses
        guard let localAddress = lanAddress ?? addresses.first, addresses.contains(localAddress) else {
            remoteError = "Connect this Mac to Wi-Fi or Ethernet and choose its current LAN address."; return
        }
        remoteError = nil; remoteStarting = true; saveSettings()
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path, "--root", root.path, "--lan-address", localAddress]
        process.environment = ProviderTools.environment(for: URL(fileURLWithPath: "/usr/bin/python3"))
        if let web = Bundle.main.resourceURL?.appendingPathComponent("mobile-web"),
           FileManager.default.fileExists(atPath: web.appendingPathComponent("index.html").path) {
            process.arguments?.append(contentsOf: ["--web-root", web.path])
        }
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] ended in Task { @MainActor in
            guard self?.remoteProcess === ended else { return }
            if ended.terminationStatus != 0 && ended.terminationReason == .exit { self?.remoteError = "Phone bridge exited unexpectedly. Check Python 3 availability and the Mac’s LAN address." }
            self?.remoteRunning = false; self?.remoteStarting = false; self?.remoteURL = nil; self?.remoteProcess = nil
        } }
        do { try process.run(); remoteProcess = process }
        catch { remoteStarting = false; remoteError = "Could not start the Python remote bridge."; return }
        Task { [weak self, weak process] in
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, let process, process.isRunning, self.remoteProcess === process else { return }
                if let data = try? Data(contentsOf: self.root.appendingPathComponent("remote-connection.json")),
                   let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   (value["pid"] as? Int32) == process.processIdentifier,
                   value["transport"] as? String == "lan", value["listenHost"] as? String == localAddress,
                   let port = value["port"] as? Int, let token = value["token"] as? String {
                    self.remotePort = port; self.remoteRunning = true
                    self.remoteListenHost = (value["listenHost"] as? String) ?? "127.0.0.1"
                    let address = "http://\(localAddress):\(port)"
                    self.remoteURL = URL(string: "\(address)/#\(token)"); self.remoteStarting = false
                    return
                }
            }
            self?.remoteError = "The remote bridge did not start. Check Python 3 availability."; self?.stopRemote()
        }
    }
    func stopRemote() { remoteProcess?.terminate(); remoteRunning = false; remoteStarting = false; remoteURL = nil }
    var localRemoteURL: URL? { remoteURL }
    func shutdown() { notesTask?.cancel(); saveNotes(); saveFeedback(); stopRemote() }
}
