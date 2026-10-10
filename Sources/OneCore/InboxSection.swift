import Foundation

public enum InboxScope: String, CaseIterable, Identifiable {
    case review = "Needs review", running = "Running", all = "All"
    public var id: String { rawValue }
}

public struct InboxSection: Identifiable {
    public let state: AgentState
    public let title: String
    public let agents: [Agent]
    public var id: String { state.rawValue }

    public static func groups(for agents: [Agent], scope: InboxScope = .all, reviewed: [String: Date] = [:]) -> [InboxSection] {
        let states: [(AgentState, String)] = scope == .running ? [(.working, "Running")] :
            scope == .review ? [(.waiting, "Needs you"), (.done, "New results")] :
            [(.waiting, "Needs you"), (.done, "Finished"), (.working, "Running"), (.idle, "Idle"), (.offline, "Offline"), (.unknown, "History")]
        return states.compactMap { (state: AgentState, title: String) in
            let members = agents.filter { !$0.archived && $0.state == state && (scope != .review || state == .waiting || $0.updatedAt > (reviewed[$0.id] ?? .distantPast)) }.sorted {
                $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt
            }
            return members.isEmpty ? nil : InboxSection(state: state, title: title, agents: members)
        }
    }
}
