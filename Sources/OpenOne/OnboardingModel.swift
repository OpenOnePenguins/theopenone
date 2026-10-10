import AppKit
import Combine
import OneCore

@MainActor final class OnboardingModel: ObservableObject {
    struct Progress: Codable {
        var version = 1
        var step = 0
        var providers: [String] = []
        var project = ""
        var verified: [String: String] = [:]
        var completed = false
        var deferred = false
    }
    @Published private(set) var progress = Progress()
    @Published private(set) var statuses: [String: AgentConnectionStatus] = [:]
    @Published private(set) var checking = false
    @Published private(set) var verifying = false
    @Published private(set) var activeProvider: String?
    @Published var error: String?
    private let store: Store
    private let resolve: (String) -> URL?
    private let probeTimeout: TimeInterval
    private let verificationTimeout: TimeInterval
    private var generation = 0
    private var verificationTask: Task<Void, Never>?
    private var activeAgentID: String?
    private var token: AnyCancellable?
    private var file: URL { store.root.appendingPathComponent("onboarding.json") }
    static let providers = ["Claude", "Codex"]
    static let checkPrompt = "Say hello in one short sentence to confirm that this conversation is connected. Do not read or change files, run commands, or use tools."

    init(store: Store, resolve: @escaping (String) -> URL? = { ProviderTools.resolve(provider: $0) }, probeTimeout: TimeInterval = 8, verificationTimeout: TimeInterval = 90) {
        self.store = store; self.resolve = resolve; self.probeTimeout = probeTimeout; self.verificationTimeout = verificationTimeout
        if let data = try? Data(contentsOf: file) {
            do {
                let saved = try JSONDecoder().decode(Progress.self, from: data)
                if saved.version == 1 {
                    progress = saved
                    progress.providers = saved.providers.filter { Self.providers.contains($0) }
                    progress.step = min(3, max(0, saved.step))
                }
            } catch { self.error = "Setup progress couldn’t be read. Your conversations are unchanged; you can set up again." }
        }
        // CLI readiness must always be rechecked after reopening setup.
        if !progress.completed && progress.step < 3 { progress.step = 0 }
        if !progress.completed && progress.step == 3 && (!allVerified || !projectValid) { progress.step = 0 }
        token = store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
    }
    var shouldPresent: Bool { !store.demo && !progress.completed && !progress.deferred }
    var canContinue: Bool { !progress.providers.isEmpty && progress.providers.allSatisfy { statuses[$0]?.state == .ready } && !checking }
    var projectValid: Bool {
        var directory: ObjCBool = false
        return progress.project.hasPrefix("/") && FileManager.default.fileExists(atPath: progress.project, isDirectory: &directory) && directory.boolValue && FileManager.default.isReadableFile(atPath: progress.project)
    }
    var allVerified: Bool { !progress.providers.isEmpty && progress.providers.allSatisfy { verified($0) } }
    func verified(_ provider: String) -> Bool {
        guard let id = progress.verified[provider], let agent = store.agent(for: id) else { return false }
        return agent.provider == provider && agent.directory == progress.project && agent.state == .done && agent.sessionID != nil && agent.messages.contains { $0.role == "assistant" && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    func response(_ provider: String) -> String? {
        guard let id = progress.verified[provider] else { return nil }
        return store.agent(for: id)?.messages.last(where: { $0.role == "assistant" })?.text
    }
    func chooseProvider(_ provider: String, selected: Bool) {
        guard !verifying, Self.providers.contains(provider) else { return }
        if selected { if !progress.providers.contains(provider) { progress.providers.append(provider) } }
        else { progress.providers.removeAll { $0 == provider } }
        progress.completed = false; save()
    }
    func chooseProject(_ url: URL) {
        guard !verifying else { return }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if path != progress.project { progress.verified = [:] }
        progress.project = path; progress.completed = false; error = nil; save()
    }
    func advance() {
        error = nil
        if progress.step == 0 {
            guard canContinue else { error = "Choose at least one installed, signed-in agent."; return }
            progress.step = 1
        } else if progress.step == 1 {
            guard projectValid else { error = "Choose an existing project folder you can read."; return }
            progress.step = 2
        }
        save()
    }
    func back() { guard !verifying else { return }; progress.step = max(0, progress.step - 1); error = nil; save() }
    func reopen() { progress.deferred = false; progress.step = 0; error = nil; save() }
    @discardableResult func deferSetup() -> Bool {
        cancelVerification(); progress.deferred = true; return save()
    }
    func refresh() async {
        guard !checking, !verifying else { return }
        checking = true
        async let claude = OnboardingProbe.inspect(provider: "Claude", executable: resolve("Claude"), timeout: probeTimeout)
        async let codex = OnboardingProbe.inspect(provider: "Codex", executable: resolve("Codex"), timeout: probeTimeout)
        let results = await [claude, codex]
        statuses = Dictionary(uniqueKeysWithValues: results.map { ($0.provider, $0) }); checking = false
    }
    func signIn(_ provider: String) {
        guard let executable = statuses[provider]?.executable else { return }
        do {
            let folder = store.root.appendingPathComponent("setup")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let script = folder.appendingPathComponent(provider.lowercased() + "-login.command")
            try OnboardingProbe.loginScript(provider: provider, executable: executable).write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            if !NSWorkspace.shared.open(script) { error = "Couldn’t open Terminal. Run \(provider == "Claude" ? "claude auth login" : "codex login") there, then click Check again." }
        } catch { self.error = "Couldn’t prepare sign-in. Run the official CLI’s login command in Terminal, then check again." }
    }
    func verify() {
        guard !verifying else { return }
        guard canContinue, projectValid else { error = "Recheck your agents and choose an existing project folder."; return }
        guard store.pending == nil else { error = "Finish or cancel the pending reply in Inbox first."; return }
        error = nil; verifying = true; generation += 1
        let run = generation
        verificationTask = Task { [weak self] in
            guard let self else { return }
            for provider in self.progress.providers {
                guard !Task.isCancelled, self.generation == run else { return }
                if self.verified(provider) { continue }
                self.activeProvider = provider
                let previous = Set(self.store.snapshot.agents.map(\.id))
                self.store.createAgent(provider: provider, directory: self.progress.project, prompt: Self.checkPrompt)
                guard let agent = self.store.selected, !previous.contains(agent.id), self.store.pending?.agentID == agent.id else {
                    self.fail("Couldn’t start the connection check. Open Inbox for details."); return
                }
                let id = agent.id
                self.activeAgentID = id
                // Persist identity before sending, so restarting never duplicates a successful check.
                self.progress.verified[provider] = id
                guard self.save() else { self.cancelVerification(); return }
                let deadline = Date().addingTimeInterval(self.verificationTimeout)
                while Date() < deadline {
                    do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                    guard self.generation == run else { return }
                    if self.verified(provider) { break }
                    if let current = self.store.agent(for: id), current.state == .offline {
                        self.fail("\(provider) couldn’t complete the check. Check its sign-in and project permissions, then retry. Details are saved in Inbox."); return
                    }
                    if self.store.pending == nil, self.store.agent(for: id)?.state == .idle {
                        self.fail("The check was cancelled. You can retry when you’re ready."); return
                    }
                    if self.store.agent(for: id)?.state == .done {
                        self.fail("\(provider) finished without a conversation response. Update its CLI and retry; details are in Inbox."); return
                    }
                }
                guard self.verified(provider) else {
                    self.store.stopAgent(id)
                    self.fail("\(provider) didn’t respond in time. The check was stopped; inspect its conversation before retrying."); return
                }
                self.activeAgentID = nil
            }
            self.verifying = false; self.activeProvider = nil
            if self.allVerified { self.progress.step = 3; self.save() }
        }
    }
    func cancelVerification() {
        generation += 1; verificationTask?.cancel(); verificationTask = nil
        if let id = activeAgentID {
            if store.pending?.agentID == id { store.undo() }
            store.stopAgent(id)
        }
        activeAgentID = nil; verifying = false; activeProvider = nil
    }
    private func fail(_ message: String) {
        if let id = activeAgentID {
            if store.pending?.agentID == id { store.undo() }
            store.stopAgent(id)
        }
        error = message; verifying = false; activeProvider = nil; activeAgentID = nil
    }
    @discardableResult func complete() -> Bool {
        guard allVerified, projectValid else { error = "Choose an existing project and complete the connection check before finishing setup."; return false }
        progress.completed = true; progress.deferred = false
        if !save() { progress.completed = false; return false }
        if let provider = progress.providers.first, let id = progress.verified[provider] { store.selection = id }
        store.inboxScope = .all; store.tab = "Inbox"
        return true
    }
    @discardableResult private func save() -> Bool {
        do { try JSONEncoder().encode(progress).write(to: file, options: [.atomic]); return true }
        catch { self.error = "Couldn’t save setup progress. Check access to Open One’s local data folder, then retry."; return false }
    }
}
