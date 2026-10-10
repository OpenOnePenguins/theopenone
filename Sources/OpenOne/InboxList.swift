import SwiftUI
import OneCore

struct InboxList: View {
    @ObservedObject var store: Store
    var compact = false
    private let secondary = Color.white.opacity(0.76)
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(secondary)
                TextField("Search Inbox", text: $store.search).textFieldStyle(.plain).font(.system(size: 14))
                if !store.search.isEmpty { Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear Inbox search") }
            }.padding(11).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            Picker("Inbox view", selection: Binding(get: { store.inboxScope }, set: { store.setInboxScope($0) })) {
                ForEach(InboxScope.allCases) { scope in Text(scope.rawValue).tag(scope) }
            }.labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if store.inboxSections.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(store.search.isEmpty ? (store.inboxScope == .review ? "All caught up" : store.inboxScope == .running ? "No agents running" : "No conversations") : "No matches", systemImage: store.search.isEmpty ? "checkmark.circle" : "magnifyingglass")
                                    .font(.system(size: 17, weight: .semibold))
                                Text(store.search.isEmpty ? "Use All to find earlier conversations. New questions and results appear in Needs review." : "Try a conversation title, project or worktree.")
                                    .font(.system(size: 14)).foregroundStyle(secondary).lineSpacing(4)
                            }.padding(.vertical, 18)
                        }
                        ForEach(store.inboxSections) { section in
                            VStack(alignment: .leading, spacing: 9) {
                                sectionHeading(section)
                                ForEach(section.agents) { agent in row(agent).id(agent.id) }
                            }
                        }
                    }.padding(.vertical, 3)
                }.onChange(of: store.selection) { id in
                    if let id { proxy.scrollTo(id, anchor: .center) }
                }
            }
            if store.inboxScope == .review, store.inboxAgents.contains(where: { $0.state == .done }) {
                Button("Mark finished reviewed") { store.markReviewed(store.inboxAgents.filter { $0.state == .done }.map(\.id)) }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(secondary)
            }
            Button { store.tab = "Agents" } label: { Label("All tracked conversations", systemImage: "bubble.left.and.bubble.right") }
                .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(secondary)
        }.padding(16).background(Color(white: 0.085))
    }
    private func sectionHeading(_ section: InboxSection) -> some View {
        HStack(spacing: 7) {
            Text(section.title).font(.system(size: 14, weight: .semibold))
            Text("\(section.agents.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(secondary)
                .padding(.horizontal, 7).padding(.vertical, 2).background(.white.opacity(0.08), in: Capsule())
            Spacer()
        }
    }
    private func row(_ agent: Agent) -> some View {
        let selected = store.selection == agent.id
        let context = ProjectLocation(directory: agent.directory)
        let conversation = ConversationContext(agent)
        return VStack(alignment: .leading, spacing: 10) {
            Button { store.selection = agent.id; store.showingNotice = false } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 9) {
                        ProviderLogo(provider: agent.provider, size: 20).padding(.top, 1)
                        Text(agent.displayTitle).font(.system(size: 15, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    Text(context.displayName).font(.system(size: 12, weight: .medium)).foregroundStyle(secondary).lineLimit(2).multilineTextAlignment(.leading)
                    if let request = conversation.latestRequest {
                        Text("You: \(ConversationContext.excerpt(request.text, limit: 180))").font(.system(size: 12)).foregroundStyle(secondary).lineLimit(1)
                    }
                    if let message = conversation.latestResponse {
                        Text("\(agent.provider): \(ConversationContext.excerpt(message.text, limit: 180))").font(.system(size: 13)).foregroundStyle(.white.opacity(0.88)).lineLimit(1)
                    }
                    HStack {
                        Text(agent.state == .waiting ? "Reply needed" : agent.state.label)
                            .foregroundStyle(agent.state == .waiting ? Color.orange : secondary)
                        Spacer()
                        Text(agent.updatedAt, style: .relative).foregroundStyle(secondary)
                    }.font(.system(size: 12))
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Open \(agent.displayTitle), \(context.displayName), \(agent.state.label)")
            if !compact && agent.state == .waiting && !agent.choices.isEmpty && !agent.isHerdr {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(agent.choices.prefix(3).enumerated()), id: \.offset) { index, choice in
                        Button { store.stage(choice, choice: index, agentID: agent.id) } label: {
                            Text(choice).font(.system(size: 13, weight: .medium)).multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(9).background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).disabled(store.pending != nil)
                    }
                    if agent.choices.count > 3 { Text("Open chat for all \(agent.choices.count) options").font(.system(size: 12)).foregroundStyle(secondary) }
                }
            }
            if agent.state == .done && store.reviewAgents.contains(where: { $0.id == agent.id }) {
                HStack {
                    Button("Mark reviewed") { store.markReviewed([agent.id]) }
                    Spacer()
                }.buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.9))
            }
        }.padding(12).background(selected ? Color.blue.opacity(0.19) : .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? Color.blue.opacity(0.75) : .white.opacity(0.08), lineWidth: 1))
            .contextMenu {
                if agent.state == .done {
                    Button("Mark as needing review") { store.markNeedsReview(agent.id) }
                }
                Button("Remove conversation from tracking") { store.trackConversation(agent.id, enabled: false) }
                Button("Remove worktree from tracking") { store.trackWorktree(agent.directory, enabled: false) }
            }
    }
}
