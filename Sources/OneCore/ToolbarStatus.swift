import Foundation

public struct ToolbarIndicator: Identifiable, Equatable {
    public let id: String
    public let state: AgentState
}

/// In-memory completion transitions. Loading old results never creates a completion dot.
public struct ToolbarActivity: Equatable {
    private var previous: [String: AgentState] = [:]
    public private(set) var completedUntil: [String: Date] = [:]
    public init() {}
    public mutating func update(_ agents: [Agent], now: Date) {
        let live = agents.filter { !$0.archived }
        let states = Dictionary(live.map { ($0.id, $0.state) }, uniquingKeysWith: { _, last in last })
        completedUntil = completedUntil.filter { $0.value > now && states[$0.key] == .done }
        for agent in live where agent.state == .done && (previous[agent.id] == .working || previous[agent.id] == .waiting) {
            completedUntil[agent.id] = now.addingTimeInterval(20)
        }
        previous = states
    }
}

public struct ToolbarStatus: Identifiable, Equatable {
    public var id: String { provider }
    public let provider: String
    public let state: AgentState
    public let count: Int
    public let hasCompleted: Bool

    /// Exact working-conversation count, independent of brief completion signals.
    public static func runningIndicators(for agents: [Agent]) -> [ToolbarIndicator] {
        agents.filter { !$0.archived && $0.state == .working }
            .sorted { $0.id < $1.id }
            .map { ToolbarIndicator(id: $0.id, state: .working) }
    }

    /// Only active work/questions and completions observed in this app instance.
    public static func activityIndicators(for agents: [Agent], reviewed: [String: Date], completedUntil: [String: Date] = [:], now: Date = Date()) -> [ToolbarIndicator] {
        agents.filter { agent in
            !agent.archived && (agent.state == .working || agent.state == .waiting ||
                (agent.state == .done && (completedUntil[agent.id] ?? .distantPast) > now && agent.updatedAt > (reviewed[agent.id] ?? .distantPast)))
        }.sorted { $0.id < $1.id }.map { ToolbarIndicator(id: $0.id, state: $0.state) }
    }

    public static func activityLabel(for indicators: [ToolbarIndicator]) -> String {
        if indicators.isEmpty { return "No active agents" }
        return [(AgentState.working, "working"), (.waiting, "need an answer"), (.done, "just finished")]
            .compactMap { state, label in
                let count = indicators.filter { $0.state == state }.count
                return count == 0 ? nil : "\(count) \(label)"
            }.joined(separator: " · ")
    }

    public static func summaries(for agents: [Agent]) -> [ToolbarStatus] {
        let groups = Dictionary(grouping: agents.filter { !$0.archived }) { agent in
            let name = agent.provider.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name.lowercased() {
            case "claude", "claude code": return "Claude"
            case "codex": return "Codex"
            default: return name.isEmpty ? "Agent" : name
            }
        }
        return groups.map { provider, agents in
            let state: AgentState = agents.contains { $0.state == .waiting } ? .waiting
                : agents.contains { $0.state == .working } ? .working : .idle
            return ToolbarStatus(provider: provider, state: state, count: agents.count, hasCompleted: agents.contains { $0.state == .done })
        }.sorted {
            let priority: [AgentState: Int] = [.waiting: 0, .working: 1, .idle: 2]
            if $0.state != $1.state { return priority[$0.state, default: 2] < priority[$1.state, default: 2] }
            let order = ["Claude": 0, "Codex": 1]
            let a = order[$0.provider, default: 2], b = order[$1.provider, default: 2]
            return a == b ? $0.provider.localizedStandardCompare($1.provider) == .orderedAscending : a < b
        }
    }
}
