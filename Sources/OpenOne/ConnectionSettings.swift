import SwiftUI
import OneCore

struct ConnectionSettings: View {
    @ObservedObject var store: Store
    @State private var tools: [ProviderTools.Status] = []
    @State private var checking = false
    @State private var sessions: [HerdrSession] = []
    @State private var finding = false
    @State private var selectedSession = ""
    @State private var sessionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Agent connections").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(checking ? "Checking…" : "Check CLIs") { Task { await checkTools() } }.disabled(checking)
            }
            Text("Uses your installed CLIs and existing sign-in. Checking versions sends no model request.").font(.system(size: 11)).foregroundStyle(.secondary)
            ForEach(tools, id: \.provider) { tool in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: tool.issue == nil ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(tool.issue == nil ? .green : .orange)
                        Text(tool.provider).fontWeight(.medium)
                        Spacer()
                        Text(tool.version ?? "Unavailable").lineLimit(1).foregroundStyle(.secondary)
                    }
                    if let issue = tool.issue { Text(issue).foregroundStyle(.orange) }
                    if let path = tool.executable?.path { Text(path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }
                }.font(.system(size: 11)).padding(10).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            }
            Divider()
            Text("Connect existing agents with Herdr").font(.system(size: 14, weight: .semibold))
            Text("Choose a running local Herdr session to see live terminals, send tasks, and interrupt working agents. Read approval prompts and use the terminal key controls to respond.").font(.system(size: 11)).foregroundStyle(.secondary)
            if let connected = store.herdrSession {
                HStack {
                    Label(connected, systemImage: "terminal")
                    Spacer()
                    Button("Refresh") { Task { await store.refreshHerdr() } }.disabled(store.herdrRefreshing)
                    Button("Disconnect") { store.connectHerdr(session: nil); selectedSession = "" }
                }.font(.system(size: 12))
            }
            HStack {
                Button(finding ? "Finding…" : "Find sessions") { Task { await findSessions() } }.disabled(finding || store.demo)
                if !sessions.isEmpty {
                    Picker("Session", selection: $selectedSession) {
                        Text("Choose a session").tag("")
                        ForEach(sessions) { session in Text(session.name).tag(session.name) }
                    }.labelsHidden()
                    Button("Connect") { store.connectHerdr(session: selectedSession) }.disabled(selectedSession.isEmpty || store.demo)
                }
            }
            if let error = sessionError ?? store.herdrNotice { Text(error).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled) }
            Link("Herdr setup guide", destination: URL(string: "https://herdr.dev/docs/")!).font(.system(size: 11))
        }.task { await checkTools() }
    }
    private func checkTools() async {
        guard !checking else { return }
        checking = true
        async let codex = ProviderTools.inspect(provider: "Codex")
        async let claude = ProviderTools.inspect(provider: "Claude")
        tools = await [codex, claude]
        checking = false
    }
    private func findSessions() async {
        finding = true; sessionError = nil
        defer { finding = false }
        do {
            sessions = try await HerdrService().sessions().filter { $0.running && $0.connectionError == nil }
            if !sessions.contains(where: { $0.name == selectedSession }) { selectedSession = "" }
            if sessions.isEmpty { sessionError = "No running Herdr sessions found. Open Herdr first, then try again." }
        } catch { sessionError = error.localizedDescription }
    }
}

struct HerdrTerminalView: View {
    @ObservedObject var store: Store
    let agent: Agent
    @State private var followOutput = true
    @State private var showTerminal = false
    private var output: String { store.herdrOutputs[agent.id] ?? "" }
    private var terminalVisible: Bool { showTerminal || agent.sourcePath == nil || agent.state == .waiting }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(terminalVisible ? "LIVE TERMINAL" : "CONVERSATION").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Toggle("Follow", isOn: $followOutput).toggleStyle(.checkbox).font(.system(size: 10))
                Button { Task { await store.refreshHerdr(readAgentID: agent.id) } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(store.herdrRefreshing).help("Refresh terminal output")
            }
            if agent.sourcePath != nil && agent.state != .waiting {
                Picker("Conversation view", selection: $showTerminal) {
                    Text("Conversation").tag(false)
                    Text("Terminal").tag(true)
                }.pickerStyle(.segmented)
            }
            if agent.herdrConnected != true {
                Text("Disconnected. Reconnect this session in Settings.").font(.system(size: 11)).foregroundStyle(.orange)
            } else if agent.state == .waiting {
                Text("Review the terminal prompt, then choose a key to send. Escape or Undo cancels during the two-second delay.").font(.system(size: 11)).foregroundStyle(.orange)
                HStack(spacing: 8) {
                    ForEach([("up", "↑"), ("down", "↓"), ("enter", "Return"), ("esc", "Escape")], id: \.0) { key, label in
                        Button(label) { store.stageTerminalKey(key, agentID: agent.id) }
                            .help("Send \(label) to \(agent.name)").disabled(store.pending != nil)
                    }
                }.font(.system(size: 11))
            }
            if let notice = store.herdrNotice { Text(notice).font(.system(size: 10)).foregroundStyle(.orange) }
            if let refreshed = store.herdrReadTimes[agent.id] { Text("Read \(refreshed.formatted(date: .omitted, time: .standard))").font(.system(size: 9)).foregroundStyle(.secondary) }
            if terminalVisible { ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(output.isEmpty ? "Waiting for terminal output…" : output)
                            .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(height: 1).id("terminal-bottom")
                    }.padding(10)
                }.background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                    .onChange(of: output) { _ in if followOutput { proxy.scrollTo("terminal-bottom", anchor: .bottom) } }
            } } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(agent.messages) { message in
                                HStack {
                                    if message.role == "user" { Spacer(minLength: 24) }
                                    MarkdownMessageView(message.text)
                                        .padding(10).background(message.role == "user" ? Color.blue.opacity(0.2) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                                    if message.role != "user" { Spacer(minLength: 8) }
                                }
                            }
                            Color.clear.frame(height: 1).id("chat-bottom")
                        }
                    }.onAppear { proxy.scrollTo("chat-bottom", anchor: .bottom) }
                        .onChange(of: agent.messages) { _ in if followOutput { proxy.scrollTo("chat-bottom", anchor: .bottom) } }
                }
            }
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: agent.id) { await store.refreshHerdr(readAgentID: agent.id) }
    }
}
