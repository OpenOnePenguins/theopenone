import Foundation

public struct RoutingMessage: Codable, Equatable {
    public let role: String
    public let text: String
    public let date: Date
    public init(_ message: Message) {
        role = message.role; text = ConversationContext.excerpt(message.text, limit: 400); date = message.date
    }
}

public struct RoutingCandidate: Codable, Equatable {
    public var id: String
    public var name: String
    public var provider: String
    public var project: String
    public var task: String
    public var latestMessage: String
    public var worktree: String?
    public var state: AgentState
    public var latestRequest: String?
    public var recentMessages: [RoutingMessage]
    public init(_ agent: Agent) {
        id = agent.id; name = agent.name; provider = agent.provider
        let location = ProjectLocation(directory: agent.directory)
        let context = ConversationContext(agent)
        project = location.projectName; worktree = location.worktreeName; state = agent.state
        latestRequest = context.latestRequest.map { ConversationContext.excerpt($0.text, limit: 800) }
        recentMessages = context.recentMessages.map(RoutingMessage.init)
        task = String(agent.title.prefix(200))
        latestMessage = context.recentMessages.last.map { ConversationContext.excerpt($0.text, limit: 600) } ?? ""
    }
}

public struct RoutingDecision: Codable, Equatable {
    public var agentID: String?
    public var reason: String
    public var confidence: Double
    public init(agentID: String?, reason: String, confidence: Double) {
        self.agentID = agentID; self.reason = reason; self.confidence = confidence
    }
    public static func decode(_ data: Data, candidates: [RoutingCandidate]) throws -> RoutingDecision {
        let decision = try JSONDecoder().decode(RoutingDecision.self, from: data)
        guard decision.confidence.isFinite, (0...1).contains(decision.confidence), !decision.reason.isEmpty, decision.reason.count <= 500,
              decision.agentID == nil || candidates.contains(where: { $0.id == decision.agentID }) else { throw RoutingError.invalidDecision }
        return decision
    }
}

public enum RoutingError: LocalizedError {
    case invalidDecision, unavailable, failed(String), timeout
    public var errorDescription: String? {
        switch self {
        case .invalidDecision: return "The router returned an invalid recipient. Choose an agent yourself or try again."
        case .unavailable: return "Install and sign in to Claude Code to use AI routing. You can still choose an agent directly."
        case .failed(let detail): return "AI routing failed: \(detail)"
        case .timeout: return "AI routing timed out. Your request has not been sent."
        }
    }
}

/// Immediate, on-device guidance. Ambiguous matches require a choice; this never sends.
public struct RecipientRecommendation: Equatable {
    public enum Basis { case currentConversation, matchingWords, needsChoice, ai }
    public let agentID: String?
    public let reason: String
    public let basis: Basis

    public init(agentID: String?, reason: String, basis: Basis) {
        self.agentID = agentID; self.reason = reason; self.basis = basis
    }

    public static func local(text: String, candidates: [RoutingCandidate], selectedAgentID: String?) -> Self {
        let selected = candidates.first { $0.id == selectedAgentID }
        let request = text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters)
        let followups: Set<String> = ["yes", "no", "ok", "okay", "continue", "go ahead", "do it", "try again", "thanks", "thank you", "yes please", "sounds good"]
        let current = Self(agentID: selected?.id, reason: request.isEmpty ? "Your next message will continue this conversation." : "A follow-up to the conversation you have open.", basis: .currentConversation)
        if selected != nil && (request.isEmpty || followups.contains(request)) { return current }
        let terms = words(request)
        var ranked: [(id: String, score: Int, matches: [String])] = []
        for candidate in candidates {
            let fields: [(String, Int)] = [
                (candidate.task, 5),
                ([candidate.project, candidate.worktree ?? ""].joined(separator: " "), 4),
                (candidate.latestRequest ?? "", 3),
                (candidate.recentMessages.map(\.text).joined(separator: " "), 1)
            ]
            var weights: [String: Int] = [:]
            for (field, weight) in fields {
                for word in terms.intersection(words(field)) { weights[word] = max(weights[word] ?? 0, weight) }
            }
            let score = weights.values.reduce(0, +)
            ranked.append((id: candidate.id, score: score, matches: weights.keys.sorted()))
        }
        ranked.sort { left, right in
            if left.score == right.score { return left.id < right.id }
            return left.score > right.score
        }
        if let best = ranked.first, best.score >= 3 || best.matches.count >= 2 {
            if ranked.count > 1 && Double(ranked[1].score) >= Double(best.score) * 0.8 {
                return Self(agentID: nil, reason: "Several conversations match your draft. Choose one or ask AI to compare their context.", basis: .needsChoice)
            }
            let matches = best.matches.prefix(2).map { "“\($0)”" }.joined(separator: " and ")
            return Self(agentID: best.id, reason: "Matches \(matches) in this conversation.", basis: .matchingWords)
        }
        if selected != nil {
            return Self(agentID: selected?.id, reason: request.isEmpty ? current.reason : "Your current conversation. No clear word match; ask AI to compare context.", basis: .currentConversation)
        }
        if candidates.count == 1 {
            return Self(agentID: candidates[0].id, reason: "The only available conversation. Check its context before sending.", basis: .currentConversation)
        }
        return Self(agentID: nil, reason: candidates.isEmpty ? "Start an agent or wait for one to become available." : "Describe the task to find a matching conversation.", basis: .needsChoice)
    }

    private static func words(_ text: String) -> Set<String> {
        let ignored: Set<String> = ["the", "and", "for", "this", "that", "with", "from", "have", "has", "are", "was", "were", "you", "your", "our", "can", "could", "would", "should", "will", "not", "please", "now", "then", "also", "just", "want", "need", "make", "use", "using", "add", "change", "update", "fix", "help", "continue", "agent", "claude", "codex"]
        return Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 2 && !ignored.contains($0) })
    }
}
