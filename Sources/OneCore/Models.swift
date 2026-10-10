import Foundation

public enum AgentState: String, Codable, CaseIterable {
    case working, waiting, done, idle, offline, unknown
    public var label: String {
        switch self {
        case .working: return "Working"
        case .waiting: return "Needs you"
        case .done: return "Done"
        case .idle: return "Ready"
        case .offline: return "Offline"
        case .unknown: return "Last activity"
        }
    }
}

public struct Message: Codable, Identifiable, Equatable {
    public var id: String
    public var role: String
    public var text: String
    public var date: Date
    public init(role: String, text: String, id: String = UUID().uuidString, date: Date = Date()) {
        self.id = id; self.role = role; self.text = text; self.date = date
    }
}

public struct Agent: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var provider: String
    public var directory: String
    public var state: AgentState
    public var title: String
    public var messages: [Message]
    public var choices: [String]
    public var requestID: String?
    public var sessionID: String?
    public var managed: Bool
    public var updatedAt: Date
    public var archived: Bool
    public var sourcePath: String?
    public var providerHome: String?
    public var lastAcceptedMessageID: String?
    public var forkSessionID: String?
    public var herdrSession: String?
    public var herdrPaneID: String?
    public var herdrTerminalID: String?
    public var herdrIdentity: String?
    public var herdrConnected: Bool?
    public var transcriptUpdatedAt: Date?
    public var isHerdr: Bool { herdrSession != nil }
    public var displayTitle: String { title.isEmpty ? name : title }

    public var isObserved: Bool { sourcePath != nil && !managed && !isHerdr }
    public var canQueue: Bool {
        isObserved && provider == "Codex" && state != .waiting
            && sessionID.flatMap(UUID.init(uuidString:)) != nil
    }
    public var canResume: Bool {
        isObserved && ["Codex", "Claude"].contains(provider) && state != .working && state != .waiting
            && sessionID.map { !$0.isEmpty && !$0.hasPrefix("-") } == true
    }
    public var canReceive: Bool { managed || requestID != nil || (herdrConnected == true && (state == .idle || state == .done)) }
    public init(id: String, name: String, provider: String = "Agent", directory: String = "", state: AgentState = .idle, title: String = "", messages: [Message] = [], choices: [String] = [], requestID: String? = nil, sessionID: String? = nil, managed: Bool = false, updatedAt: Date = Date(), archived: Bool = false, sourcePath: String? = nil, forkSessionID: String? = nil, providerHome: String? = nil) {
        self.id = id; self.name = name; self.provider = provider; self.directory = directory
        self.state = state; self.title = title; self.messages = messages; self.choices = choices
        self.requestID = requestID; self.sessionID = sessionID; self.managed = managed
        self.updatedAt = updatedAt; self.archived = archived
        self.sourcePath = sourcePath; self.forkSessionID = forkSessionID
        self.providerHome = providerHome
        self.herdrSession = nil; self.herdrPaneID = nil; self.herdrTerminalID = nil; self.herdrConnected = nil
    }
}

/// An event is written atomically to events/<uuid>.json by the bridge.
public struct AgentEvent: Codable {
    public var id: String
    public var agentID: String
    public var kind: String
    public var name: String?
    public var provider: String?
    public var directory: String?
    public var text: String?
    public var choices: [String]?
    public var requestID: String?
    public init(id: String = UUID().uuidString, agentID: String, kind: String, name: String? = nil, provider: String? = nil, directory: String? = nil, text: String? = nil, choices: [String]? = nil, requestID: String? = nil) {
        self.id = id; self.agentID = agentID; self.kind = kind; self.name = name
        self.provider = provider; self.directory = directory; self.text = text
        self.choices = choices; self.requestID = requestID
    }
    public var isValid: Bool {
        !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !agentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ["register", "working", "question", "message", "done", "offline"].contains(kind)
            && (kind != "question" || (!(requestID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !(text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
    }
}

public struct AgentReply: Codable, Equatable {
    public var agentID: String
    public var requestID: String
    public var text: String
    public var choiceIndex: Int?
    public init(agentID: String, requestID: String, text: String, choiceIndex: Int? = nil) {
        self.agentID = agentID; self.requestID = requestID; self.text = text; self.choiceIndex = choiceIndex
    }
}

public struct Snapshot: Codable {
    public var agents: [Agent]
    public var processedEventIDs: [String]
    public init(agents: [Agent] = [], processedEventIDs: [String] = []) {
        self.agents = agents; self.processedEventIDs = processedEventIDs
    }
    @discardableResult public mutating func apply(_ event: AgentEvent) -> Bool {
        guard event.isValid, !processedEventIDs.contains(event.id) else { return false }
        if !agents.contains(where: { $0.id == event.agentID }) {
            agents.append(Agent(id: event.agentID, name: event.name ?? event.agentID))
        }
        let i = agents.firstIndex(where: { $0.id == event.agentID })!
        if let name = event.name { agents[i].name = name }
        if let provider = event.provider { agents[i].provider = provider }
        if let directory = event.directory { agents[i].directory = directory }
        if let text = event.text, !text.isEmpty {
            agents[i].messages.append(Message(role: "assistant", text: text, id: event.id))
            agents[i].title = String(text.prefix(80))
        }
        switch event.kind {
        case "question":
            agents[i].state = .waiting
            agents[i].requestID = event.requestID
            agents[i].choices = event.choices ?? []
        case "working": agents[i].state = .working
        case "done": agents[i].state = .done
        case "offline": agents[i].state = .offline
        default: break
        }
        if ["working", "done", "offline"].contains(event.kind) {
            agents[i].requestID = nil; agents[i].choices = []
        }
        agents[i].archived = false
        agents[i].updatedAt = Date()
        processedEventIDs.append(event.id)
        if processedEventIDs.count > 10_000 { processedEventIDs.removeFirst(processedEventIDs.count - 10_000) }
        return true
    }

    /// A deterministic suggestion only. The UI always shows the recipient before sending.
    public func suggestedAgent(for text: String) -> String? {
        let words = Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 2 })
        let scored = agents.filter { !$0.archived && $0.state != .offline }.map { agent -> (String, Int) in
            let context = "\(agent.name) \(agent.title) \(agent.directory)".lowercased()
            return (agent.id, words.reduce(0) { $0 + (context.contains($1) ? 1 : 0) })
        }.sorted { $0.1 > $1.1 }
        guard let first = scored.first, first.1 > 0, scored.count == 1 || scored[1].1 < first.1 else { return nil }
        return first.0
    }
}

public enum BridgePaths {
    public static var root: URL {
        if let override = ProcessInfo.processInfo.environment["OPEN_ONE_HOME"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Open One", isDirectory: true)
    }
    public static func prepare(_ root: URL) throws {
        for directory in [root, root.appendingPathComponent("events"), root.appendingPathComponent("replies"), root.appendingPathComponent("rejected")] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }
    public static func safeFilename(_ value: String) -> String {
        Data(value.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "")
    }
}
