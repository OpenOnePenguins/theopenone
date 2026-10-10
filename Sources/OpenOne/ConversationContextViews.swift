import SwiftUI
import OneCore

struct MessageByline: View {
    let message: Message
    let provider: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(message.role == "user" ? "You" : message.role == "assistant" ? provider : "Update").fontWeight(.semibold)
            Spacer(minLength: 5)
            Text(message.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                .help(message.date.formatted(date: .complete, time: .standard))
        }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
    }
}

struct LatestRequestView: View {
    let agent: Agent
    var compact = false
    var body: some View {
        if let request = ConversationContext(agent).latestRequest {
            VStack(alignment: .leading, spacing: 4) {
                if !compact { Text("Your latest request").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.65)) }
                Text((compact ? "You: " : "") + ConversationContext.excerpt(request.text, limit: 500)).font(.system(size: compact ? 12 : 13))
                    .lineLimit(compact ? 1 : 2).frame(maxWidth: .infinity, alignment: .leading).help(request.text)
            }.padding(compact ? 8 : 10).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct RecipientRecommendationView: View {
    @ObservedObject var store: Store
    let choose: () -> Void
    @State private var showingReason = false

    var body: some View {
        let recommendation = store.recipientRecommendation
        let agent = recommendation.agentID.flatMap { id in store.routingCandidates.first { $0.id == id } }
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("Recommended recipient").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Button { showingReason.toggle() } label: {
                    HStack(spacing: 3) { Text("Why?"); Image(systemName: showingReason ? "chevron.up" : "chevron.down").font(.system(size: 8)) }
                        .font(.system(size: 11))
                }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Why this recipient?")
                Spacer(minLength: 4)
                if store.routing {
                    ProgressView().controlSize(.mini)
                    Button("Cancel") { store.cancelRouting() }.buttonStyle(.plain).font(.system(size: 11)).help("Comparing conversation context…")
                } else {
                    Button { store.suggestRecipient() } label: {
                        Label("Ask AI", systemImage: "sparkle.magnifyingglass").font(.system(size: 11, weight: .medium))
                    }.buttonStyle(.plain).foregroundStyle(.blue).accessibilityLabel("Ask AI to recommend")
                        .disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.routingCandidates.isEmpty || store.pending != nil || store.voiceRecording)
                        .help("Compare your draft with recent conversation context using Claude. This does not send your message to an agent.")
                }
            }
            HStack(alignment: .top, spacing: 9) {
                if let agent { ProviderLogo(provider: agent.provider, size: 21) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(agent?.displayTitle ?? "Choose a conversation").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        .help(agent?.displayTitle ?? recommendation.reason)
                    if let agent {
                        Text("\(agent.provider) · \(ProjectLocation(directory: agent.directory).displayName)")
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let agent, agent.id == store.selection {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(.green)
                        .help("Selected recipient").accessibilityLabel("Selected recipient")
                } else {
                    Button(agent == nil ? "Choose…" : "Use this") {
                        if agent == nil { choose() } else { store.useSuggestedRecipient() }
                    }.disabled(store.pending != nil || store.voiceRecording)
                }
            }
            if showingReason || agent == nil {
                Text(recommendation.reason).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                    .lineLimit(3).help(recommendation.reason).fixedSize(horizontal: false, vertical: true)
                if showingReason {
                    HStack {
                        Text(recommendation.basis == .ai ? (store.demo ? "Demo result" : "AI recommendation") : "On-device matching")
                        Spacer()
                        Button("Choose another…", action: choose).buttonStyle(.plain).disabled(store.voiceRecording || store.pending != nil)
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }.padding(10).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain).accessibilityLabel("Recipient recommendation")
    }
}

struct RecipientPicker: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var matches: [Agent] {
        store.activeAgents.filter { agent in
            let context = ConversationContext(agent)
            let text = [agent.displayTitle, agent.provider, agent.directory, context.latestRequest?.text ?? "", context.latestResponse?.text ?? ""].joined(separator: " ")
            return search.isEmpty || text.localizedCaseInsensitiveContains(search)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Choose a conversation").font(.system(size: 20, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            TextField("Search projects, requests or replies", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if matches.isEmpty { Text("No matching conversations").foregroundStyle(.secondary).padding(.vertical, 20) }
                    ForEach(matches) { agent in
                        let context = ConversationContext(agent)
                        Button {
                            guard store.activeAgents.contains(where: { $0.id == agent.id }) else { return }
                            store.cancelRouting(); store.selection = agent.id; dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(alignment: .top, spacing: 8) {
                                    ProviderLogo(provider: agent.provider, size: 19)
                                    Text(agent.displayTitle).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                                    Spacer(minLength: 0)
                                    if agent.id == store.selection { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
                                }
                                Text("\(agent.provider) · \(ProjectLocation(directory: agent.directory).displayName) · \(agent.state.label)")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                                if let request = context.latestRequest {
                                    Text("You: \(ConversationContext.excerpt(request.text, limit: 220))").lineLimit(2)
                                }
                                if let response = context.latestResponse {
                                    Text("\(agent.provider): \(ConversationContext.excerpt(response.text, limit: 220))").lineLimit(2).foregroundStyle(.secondary)
                                } else {
                                    Text(context.latestRequest == nil ? "No messages loaded yet" : "No reply to this request yet").foregroundStyle(.secondary)
                                }
                            }.font(.system(size: 12)).multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(.white.opacity(agent.id == store.selection ? 0.09 : 0.035), in: RoundedRectangle(cornerRadius: 10))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(20).frame(width: 420, height: 470).preferredColorScheme(.dark)
    }
}
