import Foundation

/// Context is taken from recorded messages, never inferred from an old chat title.
public struct ConversationContext {
    public let latestRequest: Message?
    public let latestResponse: Message?
    public let recentMessages: [Message]

    public init(_ agent: Agent) {
        let turns = agent.messages.filter {
            ["user", "assistant"].contains($0.role) && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let requestIndex = turns.lastIndex { $0.role == "user" }
        latestRequest = requestIndex.map { turns[$0] }
        // Do not label a previous turn's answer as the answer to a new request.
        let currentTurn = requestIndex.map { Array(turns.suffix(from: turns.index(after: $0))) } ?? turns
        latestResponse = currentTurn.last { $0.role == "assistant" }
        recentMessages = Array(turns.suffix(6))
    }

    public static func excerpt(_ text: String, limit: Int) -> String {
        let clean = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard clean.count > limit else { return clean }
        return String(clean.prefix(max(0, limit - 1))) + "…"
    }
}
