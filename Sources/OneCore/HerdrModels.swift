import Foundation

public struct HerdrSession: Codable, Equatable, Identifiable {
    public let name: String
    public let running: Bool
    public let defaultSession: Bool
    public let socketPath: String?
    public let connectionError: String?
    public var id: String { name }
    enum CodingKeys: String, CodingKey {
        case name, running
        case defaultSession = "default", socketPath = "socket_path", connectionError = "connection_error"
    }
}

public struct HerdrAgent: Codable, Equatable {
    public let paneID: String
    public let terminalID: String
    public let agentStatus: String
    public let name: String?
    public let agent: String?
    public let title: String?
    public let cwd: String?
    public let foregroundCwd: String?
    public let agentSession: HerdrAgentSession?
    /// Only native IDs with a matching provider can join a local transcript.
    /// Paths, titles and working directories are not conversation identities.
    public var nativeSessionID: String? {
        guard let session = agentSession, session.kind == "session_id",
              Self.conversationProvider(session.agent) == Self.conversationProvider(agent ?? ""),
              Self.conversationProvider(session.agent) != nil,
              !session.value.isEmpty,
              session.value == session.value.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return session.value
    }
    public static func conversationProvider(_ name: String) -> String? {
        switch name.lowercased() {
        case "claude", "claude code", "claude-code": return "claude"
        case "codex": return "codex"
        default: return nil
        }
    }
    /// Detects provider/native-session replacement even if the terminal stays alive.
    /// Without a reported native session, same-provider replacement is not distinguishable.
    public var identityFingerprint: String {
        let parts = [terminalID, agent ?? "", agentSession?.source ?? "", agentSession?.agent ?? "", agentSession?.kind ?? "", agentSession?.value ?? ""]
        return parts.map { "\($0.utf8.count):\($0)" }.joined()
    }
    public var provider: String {
        let label = agent?.lowercased() ?? ""
        if label.contains("codex") { return "Codex" }
        if label.contains("claude") { return "Claude" }
        return agent ?? "Herdr"
    }
    enum CodingKeys: String, CodingKey {
        case name, agent, title, cwd
        case agentSession = "agent_session"
        case paneID = "pane_id", terminalID = "terminal_id", agentStatus = "agent_status", foregroundCwd = "foreground_cwd"
    }
}

public struct HerdrAgentSession: Codable, Equatable {
    public let source: String
    public let agent: String
    public let kind: String
    public let value: String
}
