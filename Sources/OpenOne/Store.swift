import AppKit
import Combine
import OneCore

struct PendingReply {
    var agentID: String
    var requestID: String?
    var text: String
    var choiceIndex: Int?
    var deadline: Date
    var attachment: URL?
    var composerKey: String?
    var terminalKey: String? = nil
    var terminalIdentity: String? = nil
    var resume: ResumeTarget? = nil
    var queueTarget: QueueTarget? = nil
    var remoteCommandID: String? = nil
    var remoteConversationKey: String? = nil
    var approvalID: String? = nil
}

/// Pin the recipient while its transcript can legitimately advance during Undo.
struct QueueTarget: Equatable {
    let sessionID: String
    let providerHome: String?
    let directory: String
    let sourcePath: String?
    init?(_ agent: Agent) {
        guard agent.provider == "Codex", let id = agent.sessionID, UUID(uuidString: id) != nil else { return nil }
        sessionID = id; providerHome = agent.providerHome; directory = agent.directory; sourcePath = agent.sourcePath
    }
}

/// Capture the exact history being resumed across the undo interval.
struct ResumeTarget: Equatable {
    let sessionID: String
    let provider: String
    let directory: String
    let sourcePath: String
    let providerHome: String?
    let modified: Date
    let size: UInt64
    let fileID: UInt64

    init?(_ agent: Agent) {
        guard agent.canResume, let sessionID = agent.sessionID, let sourcePath = agent.sourcePath,
              let attributes = try? FileManager.default.attributesOfItem(atPath: sourcePath),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let modified = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? NSNumber, let fileID = attributes[.systemFileNumber] as? NSNumber else { return nil }
        self.sessionID = sessionID; self.provider = agent.provider; self.directory = agent.directory
        self.sourcePath = sourcePath; self.modified = modified; self.size = size.uint64Value; self.fileID = fileID.uint64Value
        self.providerHome = agent.providerHome
    }
}

private struct StorePreferences: Codable {
    var discoveryEnabled = true
    var herdrSession: String?
    var trackedWorktreePaths: Set<String>?
    var ignoredConversationIDs: Set<String>?
    var reviewedResults: [String: Date]?
}

private struct ComposerDraft: Codable {
    var text = ""
    var attachment: URL?
}

@MainActor final class Store: ObservableObject {
    @Published var snapshot = Snapshot() {
        didSet { if toolbarActivityReady { refreshToolbarActivity() } }
    }
    private var toolbarActivityReady = false
    @Published private var toolbarActivity = ToolbarActivity()
    @Published var selection: String? { didSet { if selection != oldValue { cancelRouting() } } }
    @Published var tab = "Inbox" { didSet { if tab != oldValue { cancelRouting() } } }
    @Published var panelVisible = false
    @Published var toolbarOnRight = false
    @Published var toolbarPointerDown = false
    @Published var panelsOnAllSpaces = UserDefaults.standard.bool(forKey: "panelsOnAllSpaces")
    @Published var showingNotice = false
    @Published var voiceRecording = false
    @Published var newAgentProvider = "Codex"
    @Published var newAgentDirectory = ""
    @Published private var composers: [String: ComposerDraft] = [:]
    @Published var pending: PendingReply?
    @Published var notice: String?
    @Published private(set) var approvals: [String: [AgentApproval]] = [:]
    @Published var filter = "All"
    @Published var inboxScope: InboxScope = .review
    @Published private(set) var reviewedResults: [String: Date] = [:]
    @Published var search = ""
    @Published var showNewAgent = false
    @Published var showSettings = false
    @Published var showTracking = false
    @Published private(set) var trackedWorktreePaths: Set<String>?
    @Published private(set) var ignoredConversationIDs: Set<String> = []
    @Published var compact = false
    @Published var bridgeHealthy = true
    @Published var discoveryEnabled = true
    @Published var discovering = false
    @Published var discoveryNotice: String?
    @Published var forkSourceID: String?
    @Published var forkPrompt: String?
    @Published var capturing = false
    @Published var routing = false
    @Published var routeDecision: RoutingDecision?
    @Published private(set) var herdrSession: String?
    @Published private(set) var herdrRefreshing = false
    @Published private(set) var herdrNotice: String?
    @Published private(set) var herdrOutputs: [String: String] = [:]
    @Published private(set) var herdrReadTimes: [String: Date] = [:]
    private let herdrService: HerdrService
    private var nextHerdrRefresh = Date.distantPast
    private var herdrGeneration = 0
    private var herdrSending = Set<String>()
    private var herdrMutations: [String: Task<Void, Never>] = [:]
    // Keeps already-open popouts addressing the same chat when two observations join.
    private var conversationAliases: [String: String] = [:]
    let utilities: Utilities
    let root: URL
    let demo: Bool
    private var timer: Timer?
    private var undoWork: Task<Void, Never>?
    private var draftSaveWork: Task<Void, Never>?
    private var runners: [String: AgentRunner] = [:]
    private let runnerExecutable: URL?
    private let useApprovalTransport: Bool?
    private let routingExecutable: URL?
    private let discovery: SessionDiscovery?
    private let discoveryQueue = DispatchQueue(label: "openone.discovery", qos: .utility)
    private var nextDiscovery = Date.distantPast
    private let liveTranscriptQueue = DispatchQueue(label: "openone.live-transcripts", qos: .userInitiated)
    private var liveRefreshing = false
    private var recentQueueDeliveries: [String: Date] = [:]
    private var discoveryGeneration = 0
    private var shuttingDown = false
    private var storageWritable = true
    private var routingTask: Task<Void, Never>?
    private var routingService: RoutingService?
    private var routingGeneration = 0
    var onOnboardingRequested: (() -> Void)?
    var onAttention: (() -> Void)?
    var onCapture: ((String?) -> Void)?
    var onRevealInbox: (() -> Void)?
    var onReflowPanel: (() -> Void)?
    var onDockToolbar: ((Bool?) -> Void)?
    var onResizeInbox: ((CGFloat) -> Void)?

    init(root: URL = BridgePaths.root, demo: Bool = CommandLine.arguments.contains("--demo"), discovery: SessionDiscovery? = nil, herdrService: HerdrService = HerdrService(), runnerExecutable: URL? = nil, routingExecutable: URL? = nil, useApprovalTransport: Bool? = nil) {
        self.demo = demo
        self.root = root
        self.utilities = Utilities(root: root)
        self.discovery = discovery
        self.herdrService = herdrService
        self.runnerExecutable = runnerExecutable
        self.useApprovalTransport = useApprovalTransport
        self.routingExecutable = routingExecutable
        if let data = try? Data(contentsOf: root.appendingPathComponent("preferences.json")), let settings = try? JSONDecoder().decode(StorePreferences.self, from: data) {
            discoveryEnabled = settings.discoveryEnabled
            herdrSession = settings.herdrSession
            trackedWorktreePaths = settings.trackedWorktreePaths
            ignoredConversationIDs = settings.ignoredConversationIDs ?? []
            reviewedResults = settings.reviewedResults ?? [:]
        }
        do {
            try BridgePaths.prepare(root)
            let state = root.appendingPathComponent("state.json")
            if FileManager.default.fileExists(atPath: state.path) {
                let data = try Data(contentsOf: state)
                do { snapshot = try JSONDecoder().decode(Snapshot.self, from: data) }
                catch {
                    // Preserve the original bytes before allowing discovery or events to replace state.
                    let backup = root.appendingPathComponent("state-recovery-\(UUID().uuidString).json")
                    try data.write(to: backup, options: .atomic)
                    notice = "Saved unreadable local data to \(backup.lastPathComponent). Starting a fresh Inbox."
                }
                for i in snapshot.agents.indices where snapshot.agents[i].isHerdr {
                    snapshot.agents[i].herdrConnected = false
                    snapshot.agents[i].state = .offline
                }
                // Processes belong to this app instance and never survive its termination.
                for i in snapshot.agents.indices where snapshot.agents[i].managed && (snapshot.agents[i].state == .working || (snapshot.agents[i].state == .waiting && snapshot.agents[i].requestID == nil)) {
                    snapshot.agents[i].state = .offline
                }
            }
        } catch { notice = "Could not load local data: \(error.localizedDescription)"; bridgeHealthy = false; storageWritable = false }
        if !demo, let data = try? Data(contentsOf: root.appendingPathComponent("drafts.json")) {
            do { composers = try JSONDecoder().decode([String: ComposerDraft].self, from: data) }
            catch {
                do {
                    try data.write(to: root.appendingPathComponent("drafts-recovery-\(UUID().uuidString).json"), options: .atomic)
                    notice = "Unreadable drafts were backed up. Your conversations are unchanged."
                } catch { storageWritable = false; notice = "Could not preserve unreadable drafts: \(error.localizedDescription)" }
            }
        }
        if demo { loadDemo() }
        else { recoverRejectedTakeovers() }
        toolbarActivityReady = true
        refreshToolbarActivity()
        selection = (tab == "Inbox" ? inboxAgents : visible).first?.id
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.pollEvents(); self.pollRemoteCommands(); self.refreshLiveTranscripts(); self.refreshDiscoveryIfNeeded(); self.refreshToolbarActivity()
                if Date() >= self.nextHerdrRefresh { await self.refreshHerdr() }
            }
        }
    }

    // Talk routes one shared composition; Inbox compositions belong to the selected agent.
    var composerKey: String { tab == "Talk" ? "talk" : selection.map { "agent:\($0)" } ?? "inbox" }
    func captureComposerKey(requested: String? = nil) -> String {
        if let requested { return canonicalComposerKey(requested) }
        // The toolbar camera belongs to the visible conversation, not always Talk.
        if tab == "Inbox", selected != nil { return composerKey }
        return "talk"
    }
    var draft: String {
        get { draft(for: composerKey) }
        set { setDraft(newValue, for: composerKey) }
    }
    var attachment: URL? {
        get { composers[composerKey]?.attachment }
        set { setAttachment(newValue, for: composerKey) }
    }
    func canonicalAgentID(_ id: String) -> String {
        var result = id
        var visited = Set<String>()
        while let next = conversationAliases[result], visited.insert(result).inserted { result = next }
        return result
    }
    func agent(for id: String) -> Agent? { snapshot.agents.first { $0.id == canonicalAgentID(id) } }
    private func canonicalComposerKey(_ key: String) -> String {
        key.hasPrefix("agent:") ? "agent:" + canonicalAgentID(String(key.dropFirst(6))) : key
    }
    func draft(for key: String) -> String { composers[canonicalComposerKey(key)]?.text ?? "" }
    func attachment(for key: String) -> URL? { composers[canonicalComposerKey(key)]?.attachment }
    func setDraft(_ text: String, for key: String) {
        let key = canonicalComposerKey(key)
        guard composers[key]?.text != text else { return }
        var composer = composers[key] ?? ComposerDraft()
        composer.text = text
        composers[key] = composer
        if key == composerKey { cancelRouting() }
        scheduleDraftSave()
    }
    func setAttachment(_ attachment: URL?, for key: String) {
        let key = canonicalComposerKey(key)
        var composer = composers[key] ?? ComposerDraft()
        guard composer.attachment != attachment else { return }
        composer.attachment = attachment
        composers[key] = composer
        scheduleDraftSave()
    }
    private func scheduleDraftSave() {
        draftSaveWork?.cancel()
        guard !demo, !shuttingDown else { return }
        draftSaveWork = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveDrafts()
        }
    }
    private func saveDrafts() {
        guard !demo, storageWritable else { return }
        do {
            let nonempty = composers.filter { !$0.value.text.isEmpty || $0.value.attachment != nil }
            try JSONEncoder().encode(nonempty).write(to: root.appendingPathComponent("drafts.json"), options: .atomic)
        } catch { notice = "Could not save drafts: \(error.localizedDescription)" }
    }

    var visible: [Agent] {
        activeAgents.filter { agent in
            (search.isEmpty || "\(agent.name) \(agent.title) \(agent.directory)".localizedCaseInsensitiveContains(search)) &&
            (filter == "All" || (filter == "Needs you" && agent.state == .waiting) || (filter == "Done" && agent.state == .done))
        }.sorted(by: AgentConversationOrder.precedes)
    }
    var selected: Agent? { snapshot.agents.first { $0.id == selection } }
    var inboxSections: [InboxSection] {
        let matches = activeAgents.filter { search.isEmpty || "\($0.name) \($0.title) \($0.directory)".localizedCaseInsensitiveContains(search) }
        return InboxSection.groups(for: matches, scope: inboxScope, reviewed: reviewedResults)
    }
    var reviewAgents: [Agent] { InboxSection.groups(for: activeAgents, scope: .review, reviewed: reviewedResults).flatMap(\.agents) }
    func setInboxScope(_ scope: InboxScope) {
        inboxScope = scope
        if !inboxAgents.contains(where: { $0.id == selection }) { selection = inboxAgents.first?.id }
    }
    func markReviewed(_ ids: [String]) {
        for agent in activeAgents where ids.contains(agent.id) && agent.state == .done {
            reviewedResults[agent.id] = agent.updatedAt
        }
        if inboxScope == .review, !inboxAgents.contains(where: { $0.id == selection }) { selection = inboxAgents.first?.id }
        savePreferences()
    }
    func markNeedsReview(_ id: String) {
        reviewedResults.removeValue(forKey: id)
        savePreferences()
    }
    func clearInboxSelected() {
        guard let selected else { return }
        if selected.state == .done { markReviewed([selected.id]) } else { archiveSelected() }
    }
    var inboxAgents: [Agent] { inboxSections.flatMap(\.agents) }
    var activeAgents: [Agent] { snapshot.agents.filter { !$0.archived && isTracked($0) && (!($0.isObserved) || discoveryEnabled) }.sorted(by: AgentConversationOrder.precedes) }
    var knownWorktreePaths: [String] {
        Set(snapshot.agents.map { ProjectLocation(directory: $0.directory).trackingPath })
            .union(trackedWorktreePaths ?? []).filter { !$0.isEmpty }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    var removedConversations: [Agent] { snapshot.agents.filter { ignoredConversationIDs.contains($0.id) }.sorted(by: AgentConversationOrder.precedes) }
    func isTracked(_ agent: Agent) -> Bool {
        !ignoredConversationIDs.contains(agent.id) && (trackedWorktreePaths?.contains(ProjectLocation(directory: agent.directory).trackingPath) ?? true)
    }
    func setTrackAllWorktrees(_ enabled: Bool) {
        trackedWorktreePaths = enabled ? nil : Set(knownWorktreePaths)
        trackingChanged()
    }
    func trackWorktree(_ path: String, enabled: Bool) {
        let key = ProjectLocation(directory: path).trackingPath
        guard !key.isEmpty else { return }
        if trackedWorktreePaths == nil { trackedWorktreePaths = Set(knownWorktreePaths) }
        if enabled { trackedWorktreePaths?.insert(key) } else { trackedWorktreePaths?.remove(key) }
        trackingChanged()
    }
    func trackOnlyWorktree(_ path: String) {
        let key = ProjectLocation(directory: path).trackingPath
        guard !key.isEmpty else { return }
        trackedWorktreePaths = [key]; trackingChanged()
    }
    func removeAllTrackedWorktrees() { trackedWorktreePaths = []; trackingChanged() }
    func trackConversation(_ id: String, enabled: Bool) {
        let id = canonicalAgentID(id)
        guard let agent = agent(for: id) else { return }
        if enabled {
            ignoredConversationIDs.remove(id)
            if trackedWorktreePaths != nil { trackedWorktreePaths?.insert(ProjectLocation(directory: agent.directory).trackingPath) }
            if let i = snapshot.agents.firstIndex(where: { $0.id == id }) { snapshot.agents[i].archived = false }
        } else { ignoredConversationIDs.insert(id) }
        trackingChanged(); save()
    }
    private func trackingChanged() {
        refreshToolbarActivity()
        if let pending, let target = agent(for: pending.agentID), !isTracked(target) { undo() }
        cancelRouting()
        if let selected, !isTracked(selected) { selection = (tab == "Inbox" ? inboxAgents : visible).first?.id }
        discoveryGeneration += 1; nextDiscovery = .distantPast
        savePreferences()
        refreshDiscoveryIfNeeded(force: true)
    }
    var toolbarStatuses: [ToolbarStatus] { ToolbarStatus.summaries(for: activeAgents) }
    var inboxNeedsAttention: Bool { notice != nil || !reviewAgents.isEmpty }
    func refreshToolbarActivity(now: Date = Date()) {
        var next = toolbarActivity
        next.update(activeAgents, now: now)
        if next != toolbarActivity { toolbarActivity = next }
    }
    var toolbarIndicators: [ToolbarIndicator] {
        ToolbarStatus.activityIndicators(for: activeAgents, reviewed: reviewedResults, completedUntil: toolbarActivity.completedUntil)
    }
    var runningToolbarIndicators: [ToolbarIndicator] { ToolbarStatus.runningIndicators(for: activeAgents) }
    var waitingCount: Int { activeAgents.filter { $0.state == .waiting }.count }
    var routingCandidates: [Agent] { activeAgents.filter { canSend(to: $0) } }
    var recipientRecommendation: RecipientRecommendation {
        let candidates = routingCandidates
        if let decision = routeDecision, decision.agentID == nil || candidates.contains(where: { $0.id == decision.agentID }) {
            return RecipientRecommendation(agentID: decision.agentID, reason: decision.reason, basis: .ai)
        }
        return .local(text: draft, candidates: candidates.map(RoutingCandidate.init), selectedAgentID: selection)
    }

    func canSend(to agent: Agent) -> Bool {
        isTracked(agent) && runners[agent.id] == nil && !herdrSending.contains(agent.id)
            && (agent.state != .working || agent.canQueue)
            && (agent.canReceive || agent.canResume || agent.canQueue || demo)
    }

    func suggestRecipient() {
        cancelRouting()
        let request = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        let candidates = routingCandidates.map(RoutingCandidate.init)
        guard !candidates.isEmpty else { notice = "Start an agent or wait for a working agent to finish."; return }
        if demo {
            let local = RecipientRecommendation.local(text: request, candidates: candidates, selectedAgentID: selection)
            routeDecision = RoutingDecision(agentID: local.agentID, reason: "Demo suggestion based on matching words. No model was called.", confidence: 0.6)
            return
        }
        routing = true
        let generation = routingGeneration
        let service = RoutingService(executableOverride: routingExecutable)
        routingService = service
        let originalDraft = draft
        let originalComposer = composerKey
        let originalSelection = selection
        routingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.suggest(text: request, candidates: candidates, directory: self.root.appendingPathComponent("router"), selectedAgentID: originalSelection)
                guard generation == self.routingGeneration, !Task.isCancelled else { return }
                self.routing = false
                guard self.composerKey == originalComposer, self.draft == originalDraft, self.selection == originalSelection else { return }
                if let id = result.agentID, !self.routingCandidates.contains(where: { $0.id == id }) { self.notice = "The suggested agent is no longer available. Choose another agent."; return }
                self.routeDecision = result
            } catch {
                guard generation == self.routingGeneration, !Task.isCancelled else { return }
                self.routing = false
                self.notice = error.localizedDescription
            }
        }
    }

    func cancelRouting() {
        routingGeneration += 1; routingTask?.cancel(); routingService?.cancel()
        routingTask = nil; routingService = nil; routing = false; routeDecision = nil
    }

    func useSuggestedRecipient() {
        guard let id = recipientRecommendation.agentID, routingCandidates.contains(where: { $0.id == id }) else { return }
        let acceptedDecision = routeDecision
        selection = id
        if acceptedDecision?.agentID == id { routeDecision = acceptedDecision }
        // Recipient selection never sends. The user still presses Send (and can undo).
    }

    private func savePreferences() {
        guard !demo, storageWritable else { return }
        do { try JSONEncoder().encode(StorePreferences(discoveryEnabled: discoveryEnabled, herdrSession: herdrSession, trackedWorktreePaths: trackedWorktreePaths, ignoredConversationIDs: ignoredConversationIDs, reviewedResults: reviewedResults)).write(to: root.appendingPathComponent("preferences.json"), options: .atomic) }
        catch { notice = "Could not save settings: \(error.localizedDescription)" }
    }

    func connectHerdr(session: String?) {
        herdrGeneration += 1
        herdrMutations.values.forEach { $0.cancel() }
        if let pending, snapshot.agents.first(where: { $0.id == pending.agentID })?.isHerdr == true { undo() }
        herdrSession = session?.trimmingCharacters(in: .whitespacesAndNewlines)
        if herdrSession?.isEmpty == true { herdrSession = nil }
        for i in snapshot.agents.indices where snapshot.agents[i].isHerdr {
            snapshot.agents[i].herdrConnected = false; snapshot.agents[i].state = .offline
        }
        herdrOutputs = [:]; herdrReadTimes = [:]; herdrNotice = nil; nextHerdrRefresh = .distantPast
        savePreferences(); save()
        Task { await refreshHerdr() }
    }

    func refreshHerdr(readAgentID: String? = nil) async {
        guard !demo, !shuttingDown, !herdrRefreshing, let session = herdrSession else { return }
        herdrRefreshing = true
        let generation = herdrGeneration
        nextHerdrRefresh = Date().addingTimeInterval(8)
        defer { herdrRefreshing = false }
        do {
            let agents = try await herdrService.agents(session: session)
            guard generation == herdrGeneration, !shuttingDown else { return }
            mergeHerdr(agents, session: session)
            herdrNotice = nil
            let requested = readAgentID ?? selection
            if let agent = snapshot.agents.first(where: { $0.id == requested }), agent.herdrConnected == true, let pane = agent.herdrPaneID {
                do {
                    let output = try await herdrService.read(session: session, pane: pane)
                    guard generation == herdrGeneration, !shuttingDown else { return }
                    herdrOutputs[agent.id] = String(output.suffix(32_000))
                    herdrReadTimes[agent.id] = Date()
                } catch {
                    guard generation == herdrGeneration, !shuttingDown else { return }
                    herdrOutputs[agent.id] = nil; herdrReadTimes[agent.id] = nil
                    herdrNotice = "Could not read terminal: \(error.localizedDescription)"
                }
            }
        } catch {
            guard generation == herdrGeneration, !shuttingDown else { return }
            herdrNotice = "Herdr connection unavailable: \(error.localizedDescription)"
            for i in snapshot.agents.indices where snapshot.agents[i].herdrSession == session {
                snapshot.agents[i].herdrConnected = false; snapshot.agents[i].state = .offline
            }
            herdrOutputs = [:]; herdrReadTimes = [:]; save()
        }
    }

    func mergeHerdr(_ agents: [HerdrAgent], session: String) {
        guard session == herdrSession else { return }
        let old = snapshot.agents
        for i in snapshot.agents.indices where snapshot.agents[i].isHerdr {
            snapshot.agents[i].herdrConnected = false; snapshot.agents[i].state = .offline
        }
        for live in agents {
            let baseID = "herdr:" + BridgePaths.safeFilename(session + "\n" + live.paneID + "\n" + live.terminalID)
            let exactOccupant = old.first { $0.herdrSession == session && $0.herdrPaneID == live.paneID && $0.herdrTerminalID == live.terminalID && $0.herdrIdentity == live.identityFingerprint }
            let nativeMatches = old.filter { $0.herdrSession == session && live.nativeSessionID != nil && $0.sessionID == live.nativeSessionID && HerdrAgent.conversationProvider($0.provider) == HerdrAgent.conversationProvider(live.provider) }
            let liveMatches = agents.filter { live.nativeSessionID != nil && $0.nativeSessionID == live.nativeSessionID && $0.provider == live.provider }
            let occupant = exactOccupant ?? (nativeMatches.count == 1 && liveMatches.count == 1 ? nativeMatches.first : nil)
            // An existing terminal can host a new conversation without changing its ID.
            let id = occupant?.id ?? (old.contains { $0.id == baseID } ? baseID + ":" + BridgePaths.safeFilename(live.identityFingerprint) : baseID)
            let previous = old.first { $0.id == id }
            var agent = previous ?? Agent(id: id, name: live.name ?? live.paneID, provider: live.provider)
            agent.name = live.name ?? live.paneID
            agent.provider = live.provider
            agent.directory = live.foregroundCwd ?? live.cwd ?? ""
            if agent.sourcePath == nil { agent.title = live.title ?? agent.title }
            agent.sessionID = live.nativeSessionID
            switch live.agentStatus {
            case "idle": agent.state = .idle
            case "done": agent.state = .done
            case "working": agent.state = .working
            case "blocked": agent.state = .waiting
            default: agent.state = .unknown
            }
            if herdrSending.contains(id) { agent.state = .working }
            if previous?.state != agent.state { agent.updatedAt = Date() }
            if previous?.state != agent.state { agent.archived = false }
            agent.herdrSession = session; agent.herdrPaneID = live.paneID
            agent.herdrTerminalID = live.terminalID; agent.herdrConnected = true
            agent.herdrIdentity = live.identityFingerprint
            if let i = snapshot.agents.firstIndex(where: { $0.id == id }) { snapshot.agents[i] = agent }
            else { snapshot.agents.append(agent) }
        }
        joinHerdrTranscripts()
        let connectedIDs = Set(snapshot.agents.filter { $0.herdrConnected == true }.map(\.id))
        herdrOutputs = herdrOutputs.filter { connectedIDs.contains($0.key) }
        herdrReadTimes = herdrReadTimes.filter { connectedIDs.contains($0.key) }
        if selection == nil { selection = (tab == "Inbox" ? inboxAgents : visible).first?.id }
        if old != snapshot.agents { save() }
    }

    private func sendHerdr(_ reply: PendingReply, agent: Agent) {
        let ready = reply.terminalKey == nil ? agent.canReceive : agent.state == .waiting
        guard ready, agent.herdrIdentity == reply.terminalIdentity, agent.herdrConnected == true, let session = agent.herdrSession, session == herdrSession,
              let pane = agent.herdrPaneID, let terminal = agent.herdrTerminalID, !herdrSending.contains(agent.id), herdrMutations[agent.id] == nil else {
            notice = "The terminal is no longer ready. Refresh its status and review before sending."
            return
        }
        let generation = herdrGeneration
        herdrSending.insert(agent.id)
        if let i = snapshot.agents.firstIndex(where: { $0.id == agent.id }) { snapshot.agents[i].state = .working }
        herdrMutations[agent.id] = Task {
            defer { herdrSending.remove(agent.id); herdrMutations[agent.id] = nil }
            do {
                if let key = reply.terminalKey {
                    try await herdrService.sendKey(session: session, pane: pane, terminalID: terminal, key: key, expectedIdentity: reply.terminalIdentity)
                } else {
                    _ = try await herdrService.prompt(session: session, pane: pane, terminalID: terminal, text: reply.text, expectedIdentity: reply.terminalIdentity)
                }
                guard !shuttingDown, generation == herdrGeneration, let i = snapshot.agents.firstIndex(where: { $0.id == agent.id }) else { return }
                snapshot.agents[i].messages.append(Message(role: reply.terminalKey == nil ? "user" : "system", text: reply.terminalKey.map { "Sent terminal key: \($0)." } ?? reply.text))
                snapshot.agents[i].updatedAt = Date()
                if let key = reply.composerKey, draft(for: key) == reply.text { setDraft("", for: key) }
                notice = reply.terminalKey == nil ? "Prompt submitted to \(agent.name). Terminal activity will refresh shortly." : "Terminal key sent to \(agent.name)."
                save()
                herdrSending.remove(agent.id)
                await refreshHerdr(readAgentID: agent.id)
            } catch {
                guard generation == herdrGeneration, !shuttingDown else { return }
                if let i = snapshot.agents.firstIndex(where: { $0.id == agent.id }) {
                    snapshot.agents[i].state = .offline; snapshot.agents[i].herdrConnected = false
                }
                herdrOutputs[agent.id] = nil; herdrReadTimes[agent.id] = nil
                notice = "Terminal delivery could not be confirmed: \(error.localizedDescription). Check the terminal before retrying."
                save()
            }
        }
    }

    func setDiscoveryEnabled(_ enabled: Bool) {
        discoveryEnabled = enabled
        discoveryGeneration += 1
        nextDiscovery = .distantPast
        if !demo {
            savePreferences()
        }
        if !enabled && selected?.isObserved == true { selection = activeAgents.first?.id }
        refreshDiscoveryIfNeeded()
    }

    func refreshDiscoveryIfNeeded(force: Bool = false) {
        guard !demo, !shuttingDown, discoveryEnabled, let discovery, !discovering, force || Date() >= nextDiscovery else { return }
        discovering = true
        nextDiscovery = Date().addingTimeInterval(15)
        let generation = discoveryGeneration
        let trackedPaths = trackedWorktreePaths
        discoveryQueue.async { [weak self] in
            let result = discovery.scan(trackedWorktreePaths: trackedPaths)
            Task { @MainActor in
                guard let self else { return }
                self.discovering = false
                guard !self.shuttingDown, self.discoveryEnabled, generation == self.discoveryGeneration else { return }
                self.mergeDiscovered(result)
            }
        }
    }

    func refreshLiveTranscripts() {
        guard !demo, !shuttingDown, discoveryEnabled, !liveRefreshing else { return }
        let now = Date()
        recentQueueDeliveries = recentQueueDeliveries.filter { $0.value > now }
        let candidates = activeAgents.filter {
            $0.isObserved && ($0.id == selection || $0.state == .working || recentQueueDeliveries[$0.id] != nil)
        }.sorted {
            let left = $0.id == selection ? 2 : (recentQueueDeliveries[$0.id] != nil ? 1 : 0)
            let right = $1.id == selection ? 2 : (recentQueueDeliveries[$1.id] != nil ? 1 : 0)
            return left == right ? $0.updatedAt > $1.updatedAt : left > right
        }
        let targets = Array(candidates.prefix(8))
        guard !targets.isEmpty else { return }
        liveRefreshing = true
        let generation = discoveryGeneration
        liveTranscriptQueue.async { [weak self] in
            let updates = targets.compactMap { original in
                SessionDiscovery.refresh(original).map { (original, $0) }
            }
            Task { @MainActor in
                guard let self else { return }
                self.liveRefreshing = false
                guard !self.shuttingDown, self.discoveryEnabled, generation == self.discoveryGeneration else { return }
                var changed = false
                for (original, incoming) in updates {
                    guard let i = self.snapshot.agents.firstIndex(where: { $0.id == original.id }) else { continue }
                    let current = self.snapshot.agents[i]
                    guard current.isObserved, self.isTracked(current), !current.archived,
                          current.sessionID == original.sessionID, current.providerHome == original.providerHome,
                          current.sourcePath == original.sourcePath, current.provider == original.provider,
                          incoming.updatedAt > current.updatedAt else { continue }
                    var updated = incoming
                    updated.title = current.title
                    self.snapshot.agents[i] = updated
                    changed = true
                }
                if changed { self.save() }
            }
        }
    }

    func mergeDiscovered(_ result: DiscoveryResult) {
        discoveryNotice = result.warnings.isEmpty ? nil : result.warnings.joined(separator: " ")
        var changed = false
        let managedSessions = Set(snapshot.agents.filter { $0.managed }.compactMap { agent in agent.sessionID.map { "\(agent.provider):\($0)" } })
        // A newly started managed session may be discovered before its CLI emits the session ID.
        snapshot.agents.removeAll { agent in
            let duplicate = agent.isObserved && managedSessions.contains("\(agent.provider):\(agent.sessionID ?? "")")
            if duplicate { changed = true }
            return duplicate
        }
        for incoming in result.agents where !managedSessions.contains("\(incoming.provider):\(incoming.sessionID ?? "")") {
            let matches = snapshot.agents.indices.filter { snapshot.agents[$0].isHerdr && sameConversation(snapshot.agents[$0], incoming) }
            let connected = matches.filter { snapshot.agents[$0].herdrConnected == true }
            let targets = connected.isEmpty ? matches : connected
            if targets.count == 1, let i = targets.first {
                if updateTranscript(incoming, at: i) { changed = true }
                continue
            }
            if let i = snapshot.agents.firstIndex(where: { $0.id == incoming.id }) {
                guard snapshot.agents[i].isObserved else { continue }
                guard incoming.updatedAt >= snapshot.agents[i].updatedAt else { continue }
                var updated = incoming
                updated.archived = snapshot.agents[i].archived && incoming.updatedAt <= snapshot.agents[i].updatedAt
                if updated != snapshot.agents[i] { snapshot.agents[i] = updated; changed = true }
            } else {
                // A second live owner can make a previously joined chat ambiguous.
                // Its history card must no longer resolve to the old live destination.
                conversationAliases[incoming.id] = nil
                snapshot.agents.append(incoming); changed = true
            }
        }
        if joinHerdrTranscripts() { changed = true }
        let found = Set(result.agents.map(\.id))
        for i in snapshot.agents.indices where snapshot.agents[i].isObserved && !found.contains(snapshot.agents[i].id) && snapshot.agents[i].state == .working {
            snapshot.agents[i].state = .unknown; changed = true
        }
        if selection == nil || !activeAgents.contains(where: { $0.id == selection }) { selection = (tab == "Inbox" ? inboxAgents : visible).first?.id }
        if changed { save() }
    }

    private func sameConversation(_ lhs: Agent, _ rhs: Agent) -> Bool {
        guard let id = lhs.sessionID, !id.isEmpty, id == rhs.sessionID,
              let provider = HerdrAgent.conversationProvider(lhs.provider) else { return false }
        return provider == HerdrAgent.conversationProvider(rhs.provider)
    }

    @discardableResult private func updateTranscript(_ incoming: Agent, at index: Int) -> Bool {
        var current = snapshot.agents[index]
        guard current.transcriptUpdatedAt == nil || incoming.updatedAt >= current.transcriptUpdatedAt! else { return false }
        // Keep submissions newer than the transcript; older receipts are now in history.
        let recentReceipts = current.messages.filter { $0.date > incoming.updatedAt && !incoming.messages.contains($0) }
        current.messages = incoming.messages + recentReceipts
        current.title = incoming.title
        current.sourcePath = incoming.sourcePath
        current.providerHome = incoming.providerHome
        if current.directory.isEmpty { current.directory = incoming.directory }
        if incoming.updatedAt > (current.transcriptUpdatedAt ?? .distantPast) {
            current.updatedAt = max(current.updatedAt, incoming.updatedAt)
            if current.transcriptUpdatedAt != nil { current.archived = false }
        }
        current.transcriptUpdatedAt = incoming.updatedAt
        guard current != snapshot.agents[index] else { return false }
        snapshot.agents[index] = current
        return true
    }

    /// Joins only a unique live owner. Two panes claiming one native session stay separate.
    @discardableResult private func joinHerdrTranscripts() -> Bool {
        var changed = false
        for observed in snapshot.agents.filter(\.isObserved) {
            let matches = snapshot.agents.indices.filter { snapshot.agents[$0].herdrConnected == true && sameConversation(snapshot.agents[$0], observed) }
            guard matches.count == 1, let index = matches.first else { continue }
            let targetID = snapshot.agents[index].id
            let oldKey = "agent:" + observed.id, newKey = "agent:" + targetID
            // Never silently discard conflicting drafts or attachments during an upgrade.
            let oldDraft = composers[oldKey] ?? ComposerDraft()
            let newDraft = composers[newKey] ?? ComposerDraft()
            guard oldDraft.text.isEmpty || newDraft.text.isEmpty || oldDraft.text == newDraft.text,
                  oldDraft.attachment == nil || newDraft.attachment == nil || oldDraft.attachment == newDraft.attachment else { continue }
            updateTranscript(observed, at: index)
            if !oldDraft.text.isEmpty || oldDraft.attachment != nil {
                composers[newKey] = ComposerDraft(text: newDraft.text.isEmpty ? oldDraft.text : newDraft.text, attachment: newDraft.attachment ?? oldDraft.attachment)
                composers[oldKey] = nil
                scheduleDraftSave()
            }
            conversationAliases[observed.id] = targetID
            if ignoredConversationIDs.remove(observed.id) != nil { ignoredConversationIDs.insert(targetID); savePreferences() }
            if selection == observed.id { selection = targetID }
            // Observed chats cannot have a staged live reply; do not retarget any action.
            snapshot.agents.removeAll { $0.id == observed.id }
            changed = true
        }
        return changed
    }

    func save() {
        guard !demo, storageWritable else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: root.appendingPathComponent("state.json"), options: .atomic)
            bridgeHealthy = true
        } catch { bridgeHealthy = false; notice = "Could not save: \(error.localizedDescription)" }
    }

    func pollEvents() {
        guard !demo, !shuttingDown, storageWritable else { return }
        let fm = FileManager.default
        do {
            let files = try fm.contentsOfDirectory(at: root.appendingPathComponent("events"), includingPropertiesForKeys: [.creationDateKey]).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            for file in files {
                do {
                    let data = try Data(contentsOf: file)
                    guard data.count <= 1_048_576 else { throw BridgeError.invalidEvent }
                    let event = try JSONDecoder().decode(AgentEvent.self, from: data)
                    guard event.isValid else { throw BridgeError.invalidEvent }
                    var next = snapshot
                    let changed = next.apply(event)
                    // Persist before acknowledging consumption, so crash recovery replays safely.
                    try JSONEncoder().encode(next).write(to: root.appendingPathComponent("state.json"), options: .atomic)
                    snapshot = next
                    try fm.removeItem(at: file)
                    if changed && ["question", "done"].contains(event.kind), let agent = agent(for: event.agentID), isTracked(agent) { onAttention?() }
                    if selection == nil { selection = (tab == "Inbox" ? inboxAgents : visible).first?.id }
                } catch let error as DecodingError {
                    try fm.moveItem(at: file, to: root.appendingPathComponent("rejected/\(UUID().uuidString).json"))
                    notice = "An invalid agent event was moved to rejected: \(error.localizedDescription)"
                } catch BridgeError.invalidEvent {
                    try fm.moveItem(at: file, to: root.appendingPathComponent("rejected/\(UUID().uuidString).json"))
                    notice = "An invalid or oversized agent event was rejected."
                }
            }
            bridgeHealthy = true
        } catch { bridgeHealthy = false; notice = "Bridge error: \(error.localizedDescription)" }
    }

    var remoteSource = "desktop"
    func pollRemoteCommands() {
        guard utilities.remoteRunning, !shuttingDown else { return }
        publishRemoteState()
        consumeRemoteCommands()
    }

    private func publishRemoteState() {
        let agents: [[String: Any]] = activeAgents.map { agent in
            ["id": agent.id, "name": agent.name, "title": agent.displayTitle, "state": agent.state.rawValue,
             "canReceive": agent.canReceiveRemotely && approvals[agent.id]?.isEmpty != false,
             "conversationKey": agent.remoteConversationKey, "provider": agent.provider,
             "folder": ProjectLocation(directory: agent.directory).displayName,
             "readOnlyReason": approvals[agent.id]?.isEmpty == false ? "Review this command approval in Open One on your Mac." : agent.remoteReadOnlyReason,
             "requestID": agent.requestID as Any? ?? NSNull(), "choices": agent.choices,
             "messages": agent.messages.suffix(20).map { ["id": $0.id, "role": $0.role, "text": String($0.text.suffix(8000))] }]
        }
        if utilities.remoteConversationCount != agents.count { utilities.remoteConversationCount = agents.count }
        if let data = try? JSONSerialization.data(withJSONObject: ["agents": agents, "source": remoteSource]) {
            try? data.write(to: root.appendingPathComponent("remote-state.json"), options: .atomic)
        }
    }

    private func consumeRemoteCommands() {
        guard let connectionData = try? Data(contentsOf: root.appendingPathComponent("remote-connection.json")),
              let connection = try? JSONSerialization.jsonObject(with: connectionData) as? [String: Any],
              let generation = connection["generation"] as? String else { return }
        let folder = root.appendingPathComponent("remote-commands")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(20) {
            guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 65536,
                  let data = try? Data(contentsOf: file), let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = request["id"] as? String, UUID(uuidString: id) != nil,
                  file.lastPathComponent == id + ".json" else { continue }
            var message = "The agent or question changed. Refresh and try again."
            var accepted = false
            if request["generation"] as? String == generation,
               let created = request["createdAt"] as? Double, abs(Date().timeIntervalSince1970 - created) < 30,
               let agentID = request["agentID"] as? String,
               let agent = activeAgents.first(where: { $0.id == agentID }), agent.canReceiveRemotely,
               (request["conversationKey"] == nil || request["conversationKey"] as? String == agent.remoteConversationKey),
               agent.requestID == request["requestID"] as? String,
               let text = request["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 32000,
               pending == nil {
                let choice = request["choiceIndex"] as? Int
                if choice == nil || (agent.choices.indices.contains(choice!) && agent.choices[choice!] == text) {
                    stage(text, choice: choice, agentID: agentID)
                    accepted = pending?.agentID == agentID
                    if accepted { pending?.remoteCommandID = id; pending?.remoteConversationKey = agent.remoteConversationKey; message = "Sending to the agent on your Mac." }
                }
            }
            if let result = try? JSONSerialization.data(withJSONObject: ["status": accepted ? "staged" : "rejected", "message": message]) {
                try? result.write(to: root.appendingPathComponent("remote-receipts/\(id).json"), options: .atomic)
            }
            try? FileManager.default.removeItem(at: file)
            if accepted {
                // The phone's explicit Send commits now. Reuse every delivery check;
                // only the local Mac composer retains the two-second Undo interval.
                commitPending()
                publishRemoteState()
            }
        }
    }

    func stage(_ text: String, choice: Int? = nil, agentID: String? = nil, composerKeyOverride: String? = nil) {
        let sourceKey = composerKeyOverride ?? (agentID == nil ? composerKey : nil)
        let image = choice == nil ? sourceKey.flatMap { attachment(for: $0) } : nil
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && image != nil ? "Please review this screenshot." : text
        let target = agentID == nil ? selected : agent(for: agentID!)
        guard let agent = target, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard isTracked(agent) else { notice = "Add this conversation back to tracking before sending."; return }
        guard pending == nil else { notice = "Wait for the pending reply, or press Escape to undo it."; return }
        guard !shuttingDown else { return }
        if approvals[agent.id]?.isEmpty == false { notice = "Review the pending command, then choose Approve once or Deny."; return }
        guard agent.state != .working || agent.canQueue, runners[agent.id] == nil, !herdrSending.contains(agent.id), herdrMutations[agent.id] == nil else { notice = "This agent is still working. Stop it before sending a new task."; return }
        if agent.isHerdr && !agent.canReceive {
            notice = agent.state == .waiting ? "This terminal is waiting for an approval or answer. Respond in Herdr, then refresh." : "This terminal is not ready for a prompt. Refresh its status before sending."
            return
        }
        guard agent.canReceive || agent.canResume || agent.canQueue || demo else {
            notice = agent.isObserved ? "Finish or stop this session in its original app before continuing here." : "This agent has no open reply channel. It can receive an answer when it posts a question through the bridge."
            return
        }
        var queueTarget: QueueTarget?
        if !demo && agent.requestID == nil && !agent.isHerdr {
            do {
                if try (agent.canQueue && agent.state == .working) || AgentRunner.hasActiveWriter(agent) {
                    guard let target = QueueTarget(agent), validateResume(agent) else { return }
                    queueTarget = target
                }
            } catch { notice = error.localizedDescription; return }
        }
        if image != nil && !demo && (!(agent.managed || agent.canResume || agent.canQueue) || !["Codex", "Claude"].contains(agent.provider)) {
            notice = "Image attachments require a managed Codex or Claude session. Remove this attachment to send a text reply."
            return
        }
        if let image, !demo {
            do { try AgentRunner.validateImage(image, provider: agent.provider) }
            catch { notice = error.localizedDescription; return }
        }
        var resume: ResumeTarget?
        if agent.isObserved && !agent.canReceive && !demo && queueTarget == nil {
            guard let target = ResumeTarget(agent) else { notice = "This conversation's saved history is unavailable. Refresh your conversations before trying again."; return }
            guard target.modified <= agent.updatedAt else {
                notice = "This conversation has newer activity. Refreshing its history; review it before sending again."
                refreshDiscoveryIfNeeded(force: true); return
            }
            guard validateResume(agent) else { return }
            resume = target
        }
        pending = PendingReply(agentID: agent.id, requestID: agent.requestID, text: text, choiceIndex: choice, deadline: Date().addingTimeInterval(2), attachment: image, composerKey: sourceKey, terminalIdentity: agent.herdrIdentity, resume: resume, queueTarget: queueTarget)
        schedulePendingDelivery()
    }

    func stageApproval(_ requestID: String, agentID: String, allow: Bool) {
        guard !shuttingDown, pending == nil, let agent = agent(for: agentID), isTracked(agent),
              runners[agent.id] != nil, let request = approvals[agent.id]?.first(where: { $0.id == requestID }),
              !allow || request.allowEnabled else {
            notice = "This approval changed or is no longer available. Review the agent's latest request."; return
        }
        pending = PendingReply(agentID: agent.id, requestID: agent.requestID,
                               text: allow ? "Approve once" : "Deny", choiceIndex: allow ? 0 : 1,
                               deadline: Date().addingTimeInterval(2), attachment: nil, composerKey: nil,
                               approvalID: requestID)
        schedulePendingDelivery()
    }

    private func validateResume(_ agent: Agent) -> Bool {
        guard !snapshot.agents.contains(where: { $0.id != agent.id && $0.provider == agent.provider && $0.sessionID == agent.sessionID && ($0.managed || $0.herdrConnected == true) }) else {
            notice = "This session already has a connected conversation in Open One. Open that conversation to reply."; return false
        }
        var isDirectory: ObjCBool = false
        let directory = NSString(string: agent.directory).expandingTildeInPath
        guard directory.hasPrefix("/"), FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
            notice = "This conversation's project folder no longer exists. Restore the folder before continuing."; return false
        }
        guard let executable = runnerExecutable ?? ProviderTools.resolve(provider: agent.provider), FileManager.default.isExecutableFile(atPath: executable.path) else {
            notice = "Install and sign in to the \(agent.provider) CLI before continuing this conversation."; return false
        }
        return true
    }

    /// Recover failed takeovers saved by versions that cleared drafts before
    /// Codex accepted the session. Never replace a newer edited draft.
    private func recoverRejectedTakeovers() {
        guard storageWritable else { return }
        let originalSnapshot = snapshot, originalComposers = composers
        var changed = false
        for i in snapshot.agents.indices {
            let agent = snapshot.agents[i]
            guard agent.managed, agent.state == .offline, agent.provider == "Codex", agent.sourcePath != nil,
                  let userIndex = agent.messages.lastIndex(where: { $0.role == "user" }) else { continue }
            guard agent.lastAcceptedMessageID != agent.messages[userIndex].id else { continue }
            let tail = agent.messages.suffix(from: userIndex + 1)
            guard !tail.isEmpty, tail.allSatisfy({ $0.role == "system" }), tail.contains(where: { AgentRunner.isWriterConflict($0.text) }) else { continue }
            let key = "agent:" + agent.id, text = agent.messages[userIndex].text
            guard draft(for: key).isEmpty || draft(for: key) == text else { continue }
            var draft = composers[key] ?? ComposerDraft(); draft.text = text; composers[key] = draft
            snapshot.agents[i].messages.removeSubrange(userIndex...)
            snapshot.agents[i].managed = false; snapshot.agents[i].state = .unknown
            snapshot.agents[i].updatedAt = .distantPast
            changed = true
        }
        if changed {
            do {
                // Persist the recovered prompt before removing its failed bubble.
                try JSONEncoder().encode(composers).write(to: root.appendingPathComponent("drafts.json"), options: .atomic)
                notice = AgentRunner.writerBusyMessage; save()
            } catch {
                snapshot = originalSnapshot; composers = originalComposers
                notice = "Could not restore the unsent message: \(error.localizedDescription)"
            }
        }
    }

    func stageTerminalKey(_ key: String, agentID: String) {
        let agentID = canonicalAgentID(agentID)
        guard !shuttingDown, ["up", "down", "enter", "esc"].contains(key) else { return }
        guard pending == nil else { notice = "Wait for the pending action, or press Escape to undo it."; return }
        guard let agent = snapshot.agents.first(where: { $0.id == agentID }), agent.isHerdr,
              isTracked(agent),
              agent.herdrConnected == true, agent.state == .waiting, !herdrSending.contains(agent.id), herdrMutations[agent.id] == nil else {
            notice = "Refresh this terminal and review its approval or question before sending a key."
            return
        }
        pending = PendingReply(agentID: agent.id, requestID: nil, text: "Terminal key: \(key)", choiceIndex: nil, deadline: Date().addingTimeInterval(2), attachment: nil, composerKey: nil, terminalKey: key, terminalIdentity: agent.herdrIdentity)
        schedulePendingDelivery()
    }

    private func schedulePendingDelivery() {
        undoWork = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.commitPending()
        }
    }

    private func remoteReceipt(_ reply: PendingReply, status: String, message: String) {
        guard let id = reply.remoteCommandID,
              let data = try? JSONSerialization.data(withJSONObject: ["status": status, "message": message]) else { return }
        try? data.write(to: root.appendingPathComponent("remote-receipts/\(id).json"), options: .atomic)
    }

    func undo() {
        undoWork?.cancel(); undoWork = nil
        if let reply = pending { remoteReceipt(reply, status: "rejected", message: "Cancelled on your Mac. Your mobile draft is saved.") }
        pending = nil
    }

    func commitPending() {
        let remoteReply = pending
        var remoteForwarded = false
        defer {
            if let reply = remoteReply, reply.remoteCommandID != nil, !remoteForwarded {
                remoteReceipt(reply, status: "rejected", message: notice ?? "The conversation changed before delivery. Your draft is saved.")
            }
        }
        undoWork?.cancel(); undoWork = nil
        guard !shuttingDown else { pending = nil; return }
        // Read queued replacement questions before validating the captured request ID.
        pollEvents()
        guard demo || (storageWritable && bridgeHealthy) else {
            pending = nil; notice = "Reply was not sent because local data could not be saved."
            return
        }
        guard let reply = pending, let index = snapshot.agents.firstIndex(where: { $0.id == reply.agentID }) else { pending = nil; return }
        pending = nil
        let agent = snapshot.agents[index]
        guard reply.remoteConversationKey == nil || reply.remoteConversationKey == agent.remoteConversationKey else {
            notice = "This conversation changed before delivery. Reopen it on your phone."; return
        }
        if let image = reply.attachment, !demo {
            do { try AgentRunner.validateImage(image, provider: agent.provider) }
            catch { notice = error.localizedDescription; return }
        }
        guard isTracked(agent) else { notice = "Reply cancelled because this conversation is no longer tracked."; return }
        if let approvalID = reply.approvalID {
            guard let request = approvals[agent.id]?.first(where: { $0.id == approvalID }),
                  let runner = runners[agent.id], let choice = reply.choiceIndex, [0, 1].contains(choice) else {
                notice = "This command approval expired. Nothing was approved."; return
            }
            do {
                try runner.respondToApproval(approvalID, allow: choice == 0)
                snapshot.agents[index].messages.append(Message(role: "system", text: "\(reply.text): \(request.title)"))
                save()
            } catch { notice = error.localizedDescription }
            return
        }
        guard agent.state != .working || agent.canQueue, runners[agent.id] == nil, agent.requestID == reply.requestID else {
            notice = "The agent changed while this reply was pending. Review its latest message and try again."
            return
        }
        if let target = reply.queueTarget {
            guard QueueTarget(agent) == target, agent.state != .waiting, validateResume(agent) else {
                notice = "The conversation changed while this message was pending. Your draft is saved."; return
            }
            remoteForwarded = true; sendQueued(reply, agent: agent); return
        }
        if let resume = reply.resume {
            guard ResumeTarget(agent) == resume else {
                notice = "This conversation changed before the message was sent. Review its latest activity and try again."
                refreshDiscoveryIfNeeded(force: true); return
            }
            guard validateResume(agent) else { return }
        }
        if !demo && agent.requestID == nil && !agent.isHerdr {
            do {
                if try AgentRunner.hasActiveWriter(agent) {
                    guard QueueTarget(agent) != nil else { notice = AgentRunner.writerBusyMessage; return }
                    remoteForwarded = true; sendQueued(reply, agent: agent); return
                }
            } catch { notice = error.localizedDescription; return }
        }
        if reply.resume != nil {
            // Adopt only after Undo expires; keep the native ID, history and drafts.
            snapshot.agents[index].managed = true
            snapshot.agents[index].forkSessionID = nil
        }
        if agent.isHerdr && !demo {
            sendHerdr(reply, agent: agent)
            return
        }
        if let request = reply.requestID, !demo {
            do {
                let response = AgentReply(agentID: agent.id, requestID: request, text: reply.text, choiceIndex: reply.choiceIndex)
                try JSONEncoder().encode(response).write(to: root.appendingPathComponent("replies/\(BridgePaths.safeFilename(request)).json"), options: .atomic)
            } catch { notice = "Reply was not sent: \(error.localizedDescription)"; return }
        }
        remoteForwarded = true
        remoteReceipt(reply, status: snapshot.agents[index].managed && !demo ? "submitting" : "delivered", message: snapshot.agents[index].managed && !demo ? "Starting the agent on your Mac." : "Reply delivered on your Mac.")
        let submitted = Message(role: "user", text: reply.text)
        snapshot.agents[index].messages.append(submitted)
        snapshot.agents[index].choices = []
        snapshot.agents[index].requestID = nil
        snapshot.agents[index].state = .working
        snapshot.agents[index].updatedAt = Date()
        if !snapshot.agents[index].managed || demo { clearDeliveredDraft(reply) }
        save()
        if snapshot.agents[index].managed && !demo { run(agent.id, reply: reply, original: agent, submittedMessageID: submitted.id) }
        if demo {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, !self.shuttingDown, let i = self.snapshot.agents.firstIndex(where: { $0.id == agent.id }) else { return }
                self.snapshot.agents[i].messages.append(Message(role: "assistant", text: "Demo reply received. In a connected session, the agent's real response appears here."))
                self.snapshot.agents[i].state = .done
            }
        }
    }

    func archiveSelected() {
        guard let id = selection else { return }
        archiveAgent(id)
    }
    func archiveAgent(_ id: String) {
        guard let i = snapshot.agents.firstIndex(where: { $0.id == id }) else { return }
        guard snapshot.agents[i].state != .waiting, snapshot.agents[i].state != .working else {
            notice = "Answer this agent or wait for it to finish before clearing it."; return
        }
        snapshot.agents[i].archived = true
        if selection == id { selection = (tab == "Inbox" ? inboxAgents : visible).first?.id }
        save()
    }

    var archivedAgents: [Agent] { snapshot.agents.filter(\.archived).sorted { $0.updatedAt > $1.updatedAt } }

    func restoreAgent(_ id: String) {
        guard let index = snapshot.agents.firstIndex(where: { $0.id == id }) else { return }
        snapshot.agents[index].archived = false
        trackConversation(id, enabled: true)
        if snapshot.agents[index].isObserved && !discoveryEnabled { setDiscoveryEnabled(true) }
        selection = id; filter = "All"; inboxScope = .all; search = ""; tab = "Inbox"
        save()
    }

    func moveSelection(_ offset: Int) {
        let list = tab == "Inbox" ? inboxAgents : visible
        guard !list.isEmpty else { return }
        guard let current = list.firstIndex(where: { $0.id == selection }) else { selection = list.first?.id; return }
        selection = list[max(0, min(list.count - 1, current + offset))].id
    }

    func createAgent(provider: String, directory: String, prompt: String, forkFrom: Agent? = nil, image: URL? = nil) {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && image != nil ? "Please review this screenshot." : prompt
        guard !shuttingDown, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard pending == nil else { notice = "Wait for the pending reply, or press Escape to undo it."; return }
        let id = UUID().uuidString
        let ordinal = snapshot.agents.filter { $0.provider == provider }.count + 1
        let agent = Agent(id: id, name: "\(provider.lowercased())-\(ordinal)", provider: provider, directory: directory, title: String(prompt.prefix(80)), managed: true, forkSessionID: forkFrom?.sessionID, providerHome: forkFrom?.providerHome)
        if trackedWorktreePaths != nil { trackWorktree(directory, enabled: true) }
        snapshot.agents.append(agent)
        selection = id; filter = "All"; inboxScope = .all; search = ""; tab = "Inbox"; showNewAgent = false
        save()
        // Keep the first task editable if the user cancels its initial send.
        setDraft(prompt, for: composerKey)
        setAttachment(image, for: composerKey)
        stage(prompt)
    }

    func prepareFork(_ agent: Agent, prompt: String? = nil) { forkSourceID = agent.id; forkPrompt = prompt; onRevealInbox?(); showNewAgent = true }

    private func clearDeliveredDraft(_ reply: PendingReply) {
        guard let key = reply.composerKey else { return }
        if draft(for: key) == reply.text { setDraft("", for: key) }
        if composers[key]?.attachment == reply.attachment { setAttachment(nil, for: key) }
    }

    private func sendQueued(_ reply: PendingReply, agent: Agent) {
        remoteReceipt(reply, status: "submitting", message: "Sending to the existing Codex conversation.")
        let runner = AgentRunner(executableOverride: runnerExecutable)
        runners[agent.id] = runner
        notice = "Sending to Codex's queue…"
        runner.enqueue(agent: agent, prompt: utilities.promptWithNotes(reply.text), image: reply.attachment) { [weak self, weak runner] result in
            Task { @MainActor in
                guard let self, let runner, !self.shuttingDown, self.runners[agent.id] === runner else { return }
                self.runners[agent.id] = nil
                switch result {
                case .success:
                    self.remoteReceipt(reply, status: "delivered", message: "Accepted into the existing Codex conversation. Waiting for its response.")
                    self.clearDeliveredDraft(reply)
                    self.recentQueueDeliveries[agent.id] = Date().addingTimeInterval(60)
                    // Observe the owner's actual transcript; queue acceptance isn't turn completion.
                    if let i = self.snapshot.agents.firstIndex(where: { $0.id == agent.id }),
                       QueueTarget(self.snapshot.agents[i]) == QueueTarget(agent), agent.sourcePath != nil {
                        self.snapshot.agents[i].managed = false
                        self.snapshot.agents[i].updatedAt = .distantPast
                    }
                    self.notice = "Queued in Codex for \(agent.displayTitle). Its terminal can stay open; the reply appears here when it runs."
                    self.save(); self.refreshLiveTranscripts(); self.refreshDiscoveryIfNeeded(force: true)
                case .failure(let error): self.notice = error.localizedDescription
                    self.remoteReceipt(reply, status: "uncertain", message: "Delivery could not be confirmed. Check the conversation on your Mac before sending again.")
                }
            }
        }
    }

    private func acceptManagedReply(_ reply: PendingReply, messageID: String) {
        remoteReceipt(reply, status: "delivered", message: "The agent accepted your message in this conversation.")
        if let i = snapshot.agents.firstIndex(where: { $0.id == reply.agentID }) {
            snapshot.agents[i].lastAcceptedMessageID = messageID
        }
        clearDeliveredDraft(reply)
    }

    private func run(_ id: String, reply: PendingReply, original: Agent, submittedMessageID: String) {
        guard let agent = snapshot.agents.first(where: { $0.id == id }) else { return }
        let runner = AgentRunner(executableOverride: runnerExecutable, useApprovalTransport: useApprovalTransport)
        runners[id] = runner
        var writerBlocked = false
        runner.start(agent: agent, prompt: utilities.promptWithNotes(reply.text), image: reply.attachment) { [weak self, weak runner] update in
            Task { @MainActor in
                guard let self, let runner, !self.shuttingDown, self.runners[id] === runner, let i = self.snapshot.agents.firstIndex(where: { $0.id == id }) else { return }
                switch update {
                case .session(let value): self.snapshot.agents[i].sessionID = value; self.snapshot.agents[i].forkSessionID = nil; self.acceptManagedReply(reply, messageID: submittedMessageID)
                case .text(let value): self.snapshot.agents[i].messages.append(Message(role: "assistant", text: value)); self.acceptManagedReply(reply, messageID: submittedMessageID)
                case .activity(let value): self.snapshot.agents[i].title = String(value.prefix(100))
                case .approval(let request):
                    if self.approvals[id]?.contains(where: { $0.id == request.id }) != true { self.approvals[id, default: []].append(request) }
                    self.snapshot.agents[i].state = .waiting
                    if self.isTracked(self.snapshot.agents[i]) { self.onAttention?() }
                case .approvalResolved(let requestID):
                    self.approvals[id]?.removeAll { $0.id == requestID }
                    if self.pending?.agentID == id && self.pending?.approvalID == requestID { self.undo() }
                    if self.approvals[id]?.isEmpty != false { self.snapshot.agents[i].state = .working }
                case .finished(let code):
                    self.approvals[id] = nil
                    if self.pending?.agentID == id && self.pending?.approvalID != nil { self.undo() }
                    if !writerBlocked {
                        self.snapshot.agents[i].state = code == 0 ? .done : .offline
                        if code == 0 { self.acceptManagedReply(reply, messageID: submittedMessageID) }
                        else { if self.snapshot.agents[i].lastAcceptedMessageID != submittedMessageID { self.remoteReceipt(reply, status: "uncertain", message: "The agent exited before confirming delivery. Check your Mac before retrying.") }; self.snapshot.agents[i].messages.append(Message(role: "system", text: "Agent exited with status \(code). Check its CLI sign-in and permissions, then send another message to retry.")) }
                    }
                    self.runners[id] = nil
                    if self.isTracked(self.snapshot.agents[i]) { self.onAttention?() }
                case .writerBusy:
                    guard !writerBlocked else { return }
                    writerBlocked = true
                    self.remoteReceipt(reply, status: "rejected", message: AgentRunner.writerBusyMessage)
                    self.snapshot.agents[i].messages.removeAll { $0.id == submittedMessageID }
                    self.snapshot.agents[i].managed = original.managed
                    self.snapshot.agents[i].state = original.isObserved ? .unknown : .offline
                    self.notice = AgentRunner.writerBusyMessage
                    let key = reply.composerKey ?? "agent:" + id
                    if self.draft(for: key).isEmpty { self.setDraft(reply.text, for: key) }
                    if self.attachment(for: key) == nil { self.setAttachment(reply.attachment, for: key) }
                case .error(let value):
                    self.snapshot.agents[i].messages.append(Message(role: "system", text: value))
                    self.snapshot.agents[i].state = .offline
                }
                self.snapshot.agents[i].updatedAt = writerBlocked && original.isObserved ? .distantPast : Date()
                self.save()
                if writerBlocked && original.isObserved { self.refreshDiscoveryIfNeeded(force: true) }
            }
        }
    }

    func stopAgent(_ id: String) { runners[id]?.stop() }

    func stopSelected() {
        if let agent = selected, agent.isHerdr {
            guard agent.herdrConnected == true, let session = agent.herdrSession, let pane = agent.herdrPaneID, let terminal = agent.herdrTerminalID else { notice = "Reconnect this Herdr session first."; return }
            guard herdrMutations[agent.id] == nil else { notice = "A terminal action is already in progress."; return }
            let generation = herdrGeneration
            herdrMutations[agent.id] = Task {
                defer { herdrMutations[agent.id] = nil }
                do {
                    try await herdrService.interrupt(session: session, pane: pane, terminalID: terminal, expectedIdentity: agent.herdrIdentity)
                    guard generation == herdrGeneration, !shuttingDown else { return }
                    await refreshHerdr(readAgentID: agent.id)
                } catch {
                    guard generation == herdrGeneration, !shuttingDown else { return }
                    if let i = snapshot.agents.firstIndex(where: { $0.id == agent.id }) {
                        snapshot.agents[i].state = .offline; snapshot.agents[i].herdrConnected = false
                    }
                    herdrOutputs[agent.id] = nil; herdrReadTimes[agent.id] = nil
                    notice = "Interrupt could not be confirmed: \(error.localizedDescription)"
                    save()
                }
            }
            return
        }
        guard let id = selection, let runner = runners[id] else { notice = "Only sessions started by Open One can be stopped here."; return }
        runner.stop()
    }

    func shutdown() { shuttingDown = true; utilities.shutdown(); timer?.invalidate(); cancelRouting(); undo(); herdrMutations.values.forEach { $0.cancel() }; runners.values.forEach { $0.stop() }; draftSaveWork?.cancel(); saveDrafts(); save() }

    func chooseImage(for composer: String? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        let key = composer ?? composerKey
        if panel.runModal() == .OK { setAttachment(panel.url, for: key) }
    }

    func loadDemo() {
        snapshot = Snapshot(agents: [
            Agent(id: "demo-claude", name: "claude-7", provider: "Claude", directory: "~/shop/web", state: .waiting, title: "Add a pricing page", messages: [Message(role: "user", text: "Add a pricing page to the site."), Message(role: "assistant", text: "The pricing page is ready to build. Which layout would you like?\n\nThree tiers gives visitors a clear comparison and highlights the recommended plan.")], choices: ["Three tiers", "One plan", "A comparison table"], requestID: "demo-question"),
            Agent(id: "demo-codex", name: "codex-12", provider: "Codex", directory: "~/shop/api", state: .working, title: "Add Stripe checkout", messages: [Message(role: "user", text: "Add Stripe checkout to the pricing page."), Message(role: "assistant", text: "Checking the existing checkout routes and subscription model…")]),
            Agent(id: "demo-opencode", name: "opencode-3", provider: "OpenCode", directory: "~/shop/web", state: .done, title: "Fix the mobile navigation", messages: [Message(role: "assistant", text: "Mobile navigation is ready. The menu now closes after navigation, respects reduced motion, and works with the keyboard.\n\nAll 12 navigation tests pass.")]),
            Agent(id: "demo-pi", name: "pi-2", provider: "Pi", directory: "~/docs", state: .idle, title: "Update the setup guide", messages: [Message(role: "assistant", text: "Ready for your next task.")])
        ])
    }
}

enum BridgeError: Error { case invalidEvent }
