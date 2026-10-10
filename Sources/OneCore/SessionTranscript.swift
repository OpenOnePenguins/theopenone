import Foundation

/// Parses only user-visible turns. System prompts, reasoning, environment and tool output stay out of the Inbox.
public enum SessionTranscript {
    public static func parse(_ data: Data, provider: String, path: String, modified: Date, now: Date = Date()) -> Agent? {
        var sessionID: String?
        var directory = ""
        var messages: [Message] = []
        var title = ""
        var customTitle: String?
        var generatedTitle: String?
        var state: AgentState = .unknown
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let simpleFormatter = ISO8601DateFormatter()
        var lastDate = modified
        func add(_ role: String, _ text: String, _ id: String, _ date: Date) {
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            // Rollouts can contain both response_item and event_msg copies of the same message.
            if messages.last?.role == role && messages.last?.text == clean { return }
            if role == "user" && title.isEmpty { title = String(clean.prefix(100)) }
            messages.append(Message(role: role, text: String(clean.prefix(16_000)), id: id, date: date))
            if messages.count > 80 { messages.removeFirst(messages.count - 80) }
        }
        for (lineIndex, line) in data.split(separator: 10).enumerated() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            let timestamp = object["timestamp"] as? String ?? ""
            let date = formatter.date(from: timestamp) ?? simpleFormatter.date(from: timestamp) ?? modified
            let id = object["uuid"] as? String ?? "\(path):\(lineIndex)"
            let type = object["type"] as? String ?? ""
            if provider == "Codex" {
                guard let payload = object["payload"] as? [String: Any] else { continue }
                if type == "session_meta" {
                    sessionID = payload["id"] as? String
                    directory = payload["cwd"] as? String ?? directory
                } else if type == "turn_context" {
                    // Resumed sessions can change their working directory after session_meta.
                    directory = payload["cwd"] as? String ?? directory
                } else if type == "event_msg" {
                    switch payload["type"] as? String {
                    case "user_message":
                        if let text = payload["message"] as? String { add("user", text, id, date); state = .working; lastDate = date }
                    case "agent_message":
                        if let text = payload["message"] as? String { add("assistant", text, id, date); lastDate = date }
                    case "task_started", "turn_started": state = .working; lastDate = date
                    case "task_complete", "turn_complete":
                        if let text = payload["last_agent_message"] as? String { add("assistant", text, id, date) }
                        state = .done; lastDate = date
                    case "turn_aborted": state = .idle; lastDate = date
                    case "item_completed":
                        guard let item = payload["item"] as? [String: Any] else { continue }
                        // Fork rollouts may retain their parent's session_meta header.
                        // The event envelope identifies the thread that owns these turns.
                        if let threadID = payload["thread_id"] as? String, !threadID.isEmpty { sessionID = threadID }
                        let kind = item["type"] as? String ?? ""
                        let blocks = item["content"] as? [[String: Any]] ?? []
                        let text = blocks.compactMap { block -> String? in
                            guard (block["type"] as? String)?.lowercased() == "text" else { return nil }
                            return block["text"] as? String
                        }.joined(separator: "\n")
                        let itemID = item["id"] as? String ?? id
                        if kind == "UserMessage" {
                            if !text.isEmpty { add("user", text, itemID, date) }
                            state = .working; lastDate = date
                        } else if kind == "AgentMessage" {
                            let phase = item["phase"] as? String
                            if phase == nil || phase == "commentary" || phase == "final" {
                                if !text.isEmpty { add("assistant", text, itemID, date) }
                            }
                            state = phase == "final" ? .done : .working; lastDate = date
                        } else if ["CommandExecution", "McpToolCall", "FileChange", "Extension", "ImageView", "Reasoning", "ContextCompaction", "SubAgentActivity"].contains(kind), state == .working || state == .unknown {
                            // Tail reads can omit task_started. Work items establish
                            // activity without exposing tool output or reasoning.
                            state = .working; lastDate = date
                        }
                    case "token_count":
                        if state == .working { lastDate = date }
                    default: break
                    }
                } else if type == "response_item", payload["type"] as? String == "message", payload["role"] as? String == "assistant" {
                    let blocks = payload["content"] as? [[String: Any]] ?? []
                    let text = blocks.compactMap { $0["type"] as? String == "output_text" ? $0["text"] as? String : nil }.joined(separator: "\n")
                    if !text.isEmpty { add("assistant", text, id, date); lastDate = date }
                }
            } else if provider == "Claude" {
                if object["isSidechain"] as? Bool == true { continue }
                if let id = object["sessionId"] as? String { sessionID = id }
                if let cwd = object["cwd"] as? String { directory = cwd }
                if type == "custom-title", let value = object["customTitle"] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { customTitle = value }
                if type == "ai-title", let value = object["aiTitle"] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { generatedTitle = value }
                guard ["user", "assistant"].contains(type), let message = object["message"] as? [String: Any] else { continue }
                let blocks = message["content"] as? [[String: Any]] ?? []
                let text = message["content"] as? String ?? blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
                // Tool results and synthetic bookkeeping entries are not user requests.
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let synthetic = ["<task-notification>", "[Request interrupted by user", "<command-name>", "<local-command-caveat>", "<local-command-stdout>"].contains { clean.hasPrefix($0) }
                if type == "user", object["isMeta"] as? Bool != true, !synthetic, !text.isEmpty {
                    add("user", text, id, date); state = .working; lastDate = date
                } else if type == "assistant" {
                    if !text.isEmpty { add("assistant", text, id, date) }
                    let stop = message["stop_reason"] as? String
                    state = stop == "end_turn" || stop == "stop_sequence" ? .done : .working
                    lastDate = date
                }
            }
        }
        guard let sessionID, !sessionID.isEmpty, !directory.isEmpty else { return nil }
        // A transcript does not prove that its process is still alive.
        if state == .working && now.timeIntervalSince(lastDate) > 300 { state = .unknown }
        let project = URL(fileURLWithPath: directory).lastPathComponent
        return Agent(id: "observed:\(provider.lowercased()):\(sessionID)", name: "\(provider.lowercased())-\(sessionID.prefix(6))", provider: provider, directory: directory, state: state, title: String((customTitle ?? generatedTitle ?? (title.isEmpty ? project : title)).prefix(200)), messages: messages, sessionID: sessionID, updatedAt: modified, sourcePath: path)
    }
}

public struct DiscoveryResult {
    public var agents: [Agent]
    public var warnings: [String]
    public init(agents: [Agent], warnings: [String] = []) { self.agents = agents; self.warnings = warnings }
}

public final class SessionDiscovery {
    public let codexRoot: URL
    public let codexRoots: [URL]
    public let claudeRoot: URL
    private var cache: [String: (Date, Int, Agent)] = [:]
    private var titleCache: [String: (modified: Date, size: Int, titles: [String: String])] = [:]
    public init(codexRoot: URL? = nil, claudeRoot: URL? = nil, additionalCodexRoots: [URL] = []) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
        let claudeHome = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".claude")
        self.codexRoot = codexRoot ?? codexHome.appendingPathComponent("sessions")
        let defaults = codexRoot == nil ? Self.defaultCodexRoots(home: home, environment: ProcessInfo.processInfo.environment) : [self.codexRoot]
        var seen = Set<String>()
        self.codexRoots = (defaults + additionalCodexRoots).map { $0.standardizedFileURL.resolvingSymlinksInPath() }.filter { seen.insert($0.path).inserted }
        self.claudeRoot = claudeRoot ?? claudeHome.appendingPathComponent("projects")
    }

    public static func defaultCodexRoots(home: URL, environment: [String: String]) -> [URL] {
        var roots: [URL] = []
        if let configured = environment["CODEX_HOME"], configured.hasPrefix("/") {
            roots.append(URL(fileURLWithPath: configured).appendingPathComponent("sessions"))
        }
        roots += [home.appendingPathComponent(".codex/sessions"),
                  home.appendingPathComponent("Library/Application Support/orca/codex-runtime-home/home/sessions")]
        var seen = Set<String>()
        return roots.map { $0.standardizedFileURL.resolvingSymlinksInPath() }.filter { seen.insert($0.path).inserted }
    }

    /// Call on one background queue. Bounded reads keep large histories off the main thread.
    public func scan(now: Date = Date(), trackedWorktreePaths: Set<String>? = nil) -> DiscoveryResult {
        if trackedWorktreePaths?.isEmpty == true { return DiscoveryResult(agents: []) }
        let fm = FileManager.default
        var result: [Agent] = [], warnings: [String] = []
        var candidates: [(URL, String, Date, Int, String?)] = []
        for (root, provider) in codexRoots.map({ ($0, "Codex") }) + [(claudeRoot, "Claude")] {
            guard fm.fileExists(atPath: root.path) else { continue }
            let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles], errorHandler: { _, _ in
                if !warnings.contains("\(provider) history could not be fully read.") { warnings.append("\(provider) history could not be fully read.") }
                return true
            }) else { continue }
            var visited = 0
            for case let file as URL in enumerator {
                visited += 1
                if visited > 20_000 { warnings.append("\(provider) history scan reached its file limit."); break }
                // Claude subagent histories live below a session subdirectory.
                if file.lastPathComponent == "subagents" { enumerator.skipDescendants(); continue }
                guard file.pathExtension == "jsonl", let info = try? file.resourceValues(forKeys: Set(keys)), info.isRegularFile == true, info.isSymbolicLink != true,
                      let modified = info.contentModificationDate, now.timeIntervalSince(modified) <= 86400 else { continue }
                candidates.append((file, provider, modified, info.fileSize ?? 0, provider == "Codex" ? root.deletingLastPathComponent().path : nil))
            }
        }
        candidates.sort { $0.2 == $1.2 ? $0.0.path < $1.0.path : $0.2 > $1.2 }
        var seenSessions = Set<String>()
        let candidateLimit = trackedWorktreePaths == nil ? 40 : 400
        func include(_ agent: Agent, providerHome: String?) {
            var agent = agent
            agent.providerHome = providerHome
            guard seenSessions.insert(agent.id).inserted else { return }
            guard trackedWorktreePaths?.contains(ProjectLocation(directory: agent.directory).trackingPath) ?? true else { return }
            result.append(agent)
        }
        for (file, provider, modified, size, providerHome) in candidates.prefix(candidateLimit) {
            if result.count >= 40 { break }
            if let cached = cache[file.path], cached.0 == modified, cached.1 == size {
                var agent = cached.2
                if agent.state == .working && now.timeIntervalSince(modified) > 300 { agent.state = .unknown }
                include(agent, providerHome: providerHome)
                continue
            }
            do {
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                // Keep the metadata header and latest turns, without loading an entire large rollout.
                let cap = 2 * 1024 * 1024
                var data = try handle.read(upToCount: min(size, cap)) ?? Data()
                if size > cap {
                    let headerEnd = data.firstIndex(of: 10)
                    let header = headerEnd.map { Data(data[...$0]) } ?? Data()
                    try handle.seek(toOffset: UInt64(size - cap))
                    let tail = try handle.read(upToCount: cap) ?? Data()
                    data = header
                    if let newline = tail.firstIndex(of: 10) { data.append(tail.suffix(from: tail.index(after: newline))) }
                }
                if let agent = SessionTranscript.parse(data, provider: provider, path: file.path, modified: modified, now: now) {
                    cache[file.path] = (modified, size, agent)
                    include(agent, providerHome: providerHome)
                }
            } catch { warnings.append("A \(provider) transcript could not be read.") }
        }
        if trackedWorktreePaths != nil && candidates.count > candidateLimit && result.count < 40 {
            warnings.append("Checked the newest 400 transcripts for tracked worktrees; older sessions may be missing.")
        }
        let activePaths = Set(candidates.prefix(candidateLimit).map { $0.0.path })
        cache = cache.filter { activePaths.contains($0.key) }
        for root in codexRoots {
            let titles = codexTitles(root: root)
            for index in result.indices where result[index].provider == "Codex" && result[index].providerHome == root.deletingLastPathComponent().path {
                if let session = result[index].sessionID, let title = titles[session] { result[index].title = title }
            }
        }
        return DiscoveryResult(agents: result, warnings: Array(Set(warnings)).sorted())
    }

    /// Refresh a known live transcript without enumerating every provider history.
    /// Unchanged files cost only a stat; parsing stays bounded to the latest 2 MB.
    public static func refresh(_ current: Agent, now: Date = Date()) -> Agent? {
        guard current.isObserved, let path = current.sourcePath else { return nil }
        let file = URL(fileURLWithPath: path)
        guard let info = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
              info.isRegularFile == true, info.isSymbolicLink != true,
              let modified = info.contentModificationDate, modified > current.updatedAt,
              let size = info.fileSize, let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        do {
            let cap = 2 * 1024 * 1024
            var data = try handle.read(upToCount: min(size, cap)) ?? Data()
            if size > cap {
                let header = data.firstIndex(of: 10).map { Data(data[...$0]) } ?? Data()
                try handle.seek(toOffset: UInt64(size - cap))
                let tail = try handle.read(upToCount: cap) ?? Data()
                data = header
                if let newline = tail.firstIndex(of: 10) { data.append(tail.suffix(from: tail.index(after: newline))) }
            }
            guard var incoming = SessionTranscript.parse(data, provider: current.provider, path: path, modified: modified, now: now),
                  incoming.sessionID == current.sessionID else { return nil }
            incoming.id = current.id
            incoming.providerHome = current.providerHome
            incoming.title = current.title // Full discovery refreshes provider index names.
            incoming.archived = current.archived
            return incoming
        } catch { return nil }
    }

    private func codexTitles(root: URL) -> [String: String] {
        let index = root.deletingLastPathComponent().appendingPathComponent("session_index.jsonl")
        guard let info = try? index.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modified = info.contentModificationDate, let size = info.fileSize else { return [:] }
        if let cached = titleCache[index.path], cached.modified == modified, cached.size == size { return cached.titles }
        guard let handle = try? FileHandle(forReadingFrom: index) else { return [:] }
        defer { try? handle.close() }
        let cap = 4 * 1024 * 1024
        if size > cap { guard (try? handle.seek(toOffset: UInt64(size - cap))) != nil else { return [:] } }
        guard var data = try? handle.read(upToCount: cap) else { return [:] }
        if size > cap, let newline = data.firstIndex(of: 10) { data = Data(data.suffix(from: data.index(after: newline))) }
        var titles: [String: String] = [:]
        for line in data.split(separator: 10) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let id = object["id"] as? String, let title = object["thread_name"] as? String else { continue }
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { titles[id] = String(trimmed.prefix(200)) }
        }
        titleCache[index.path] = (modified, size, titles)
        return titles
    }
}
