import SwiftUI
import OneCore

/// Independently movable conversation, as seen in the reference launch video.
struct ConversationPanel: View {
    @ObservedObject var store: Store
    let agentID: String
    let close: () -> Void
    private var draftKey: String { "agent:\(agentID)" }
    private var draft: String { store.draft(for: draftKey) }
    private var attachment: URL? { store.attachment(for: draftKey) }
    private var agent: Agent? { store.agent(for: agentID) }
    var body: some View {
        VStack(spacing: 0) {
            if let agent {
                HStack(spacing: 8) {
                    StatusDot(state: agent.state)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(agent.displayTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text("\(agent.provider) · \(ProjectLocation(directory: agent.directory).displayName) · \(agent.state.label)").font(.system(size: 9)).foregroundStyle(.gray).lineLimit(1).help(agent.directory)
                    }
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(.gray) }.buttonStyle(.plain).accessibilityLabel("Close conversation")
                }.padding(13)
                Divider().opacity(0.5)
                if agent.isObserved {
                    HStack {
                        Text(agent.provider == "Codex" ? "Keep its terminal open. Messages queue in the existing Codex conversation while it is active." : "Close this session in its original app before continuing here.")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Fork…") { store.prepareFork(agent) }.help("Create a separate conversation from this history")
                    }.font(.system(size: 11)).padding(8)
                }
                LatestRequestView(agent: agent).padding(.horizontal, 12).padding(.bottom, 8)
                if agent.isHerdr { HerdrTerminalView(store: store, agent: agent) }
                else { ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(agent.messages) { message in
                                HStack {
                                    if message.role == "user" { Spacer(minLength: 25) }
                                    VStack(alignment: .leading, spacing: 6) {
                                        MessageByline(message: message, provider: agent.provider)
                                        MarkdownMessageView(message.text, fontSize: 13)
                                    }.padding(10).background(message.role == "user" ? Color.blue.opacity(0.25) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                                    if message.role != "user" { Spacer(minLength: 8) }
                                }
                            }
                            if agent.state == .waiting {
                                ForEach(Array(agent.choices.enumerated()), id: \.offset) { index, option in
                                    Button { send(option, index: index) } label: {
                                        HStack { Text("\(index + 1)").foregroundStyle(.gray); Text(option); Spacer() }.font(.system(size: 11)).padding(10).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                                    }.buttonStyle(.plain).disabled(store.pending != nil)
                                }
                            }
                            if agent.state == .working { Text("\(agent.name) is working…").font(.system(size: 10)).foregroundStyle(.gray) }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding(12)
                    }.onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                    .onChange(of: agent.messages.last?.text) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
                    .onChange(of: agent.messages.count) { _ in
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                } }
                ApprovalView(store: store, agent: agent)
                if store.pending?.agentID == store.canonicalAgentID(agentID) {
                    HStack { Text("Sending…"); Spacer(); Button("Undo") { store.undo() } }.font(.system(size: 10)).padding(10).background(.orange.opacity(0.1))
                }
                if let notice = store.notice {
                    Text(notice).font(.system(size: 10)).foregroundStyle(.orange).padding(10)
                    if notice == CaptureError.permission.localizedDescription { ScreenRecordingSettingsButton() }
                }
                if let attachment { AttachmentPreview(image: attachment) { store.setAttachment(nil, for: draftKey) }.padding(.horizontal, 12) }
                HStack(spacing: 8) {
                    Menu {
                        Button("Capture screen region…") { store.onCapture?(draftKey) }.disabled(store.capturing)
                        Button("Attach image file…") { store.chooseImage(for: draftKey) }
                    } label: { Image(systemName: "camera") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Attach screenshot")
                    TextField("Message \(agent.name)…", text: Binding(get: { draft }, set: { store.setDraft($0, for: draftKey) }), axis: .vertical).textFieldStyle(.plain).font(.system(size: 11)).lineLimit(1...4).onSubmit { send(draft) }
                    Button { send(draft) } label: { Image(systemName: "paperplane").font(.system(size: 12)) }.buttonStyle(.plain).disabled(!canSend).accessibilityLabel(agent.isObserved ? "Continue conversation and send" : "Send message")
                }.padding(12).background(.white.opacity(0.035))
            }
        }.background(PanelSurface(dark: false))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.09), .white.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1).allowsHitTesting(false))
            .preferredColorScheme(.dark)
    }
    private var canSend: Bool {
        guard let agent, (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil), store.pending == nil, !store.capturing else { return false }
        return store.canSend(to: agent)
    }
    private func send(_ text: String, index: Int? = nil) {
        guard (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil), store.pending == nil else { return }
        guard let agent, store.isTracked(agent) else { return }
        store.stage(text, choice: index, agentID: agentID, composerKeyOverride: index == nil ? draftKey : nil)
    }
}

struct AttachmentPreview: View {
    let image: URL
    let remove: () -> Void
    var body: some View {
        HStack {
            if let preview = NSImage(contentsOf: image) {
                Image(nsImage: preview).resizable().scaledToFit().frame(width: 64, height: 44).accessibilityLabel("Screenshot preview")
            }
            Text(image.lastPathComponent).font(.system(size: 10)).lineLimit(1)
            Spacer()
            Button(action: remove) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Remove attachment")
        }
    }
}

struct ScreenRecordingSettingsButton: View {
    var body: some View {
        Button("Open Screen Recording settings") {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }.font(.system(size: 11))
    }
}
