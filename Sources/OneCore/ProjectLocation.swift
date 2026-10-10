import Foundation

public struct ProjectLocation: Equatable {
    public let projectPath: String
    public let projectName: String
    public let worktreeName: String?
    public let worktreePath: String?
    public var displayName: String { worktreeName.map { "\(projectName) · \($0)" } ?? projectName }
    public var trackingPath: String { worktreePath ?? projectPath }

    public init(directory: String) {
        if let git = Self.gitLocation(directory: directory) {
            projectPath = git.project
            projectName = URL(fileURLWithPath: git.project).lastPathComponent
            worktreePath = git.worktree
            worktreeName = git.worktree.map { URL(fileURLWithPath: $0).lastPathComponent }
            return
        }
        let components = directory.split(separator: "/").map(String.init)
        // Preserve useful labels for historical sessions whose checkout no longer exists.
        if let index = components.lastIndex(of: "workspaces"), index > 0, components[index - 1] == "orca", components.count >= index + 3 {
            let project = components[index + 1]
            projectPath = (directory.hasPrefix("/") ? "/" : "") + components.prefix(index + 2).joined(separator: "/")
            projectName = project
            worktreeName = components[index + 2]
            worktreePath = (directory.hasPrefix("/") ? "/" : "") + components.prefix(index + 3).joined(separator: "/")
        } else if let index = components.lastIndex(where: { $0 == ".worktrees" }), index > 0, components.count >= index + 2 {
            projectPath = (directory.hasPrefix("/") ? "/" : "") + components.prefix(index).joined(separator: "/")
            projectName = components[index - 1]
            worktreeName = components[index + 1]
            worktreePath = (directory.hasPrefix("/") ? "/" : "") + components.prefix(index + 2).joined(separator: "/")
        } else {
            projectPath = directory
            projectName = components.last ?? "This Mac"
            worktreeName = nil
            worktreePath = nil
        }
    }

    private static func gitLocation(directory: String) -> (project: String, worktree: String?)? {
        guard directory.hasPrefix("/") else { return nil }
        var root = URL(fileURLWithPath: directory).standardizedFileURL.resolvingSymlinksInPath()
        let fm = FileManager.default
        // Read only Git's path metadata; never run commands or repository hooks.
        for _ in 0..<64 {
            let dot = root.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: dot.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue { return (root.path, nil) }
                guard let pointer = metadata(dot), pointer.hasPrefix("gitdir:") else { return nil }
                let target = String(pointer.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !target.isEmpty else { return nil }
                let gitDir = resolve(target, from: root)
                guard let commonPath = metadata(gitDir.appendingPathComponent("commondir")), !commonPath.isEmpty else {
                    // Submodules and separate git dirs are not linked worktrees.
                    return (root.path, nil)
                }
                let common = resolve(commonPath, from: gitDir)
                guard fm.fileExists(atPath: common.path) else { return nil }
                let project = common.lastPathComponent == ".git" ? common.deletingLastPathComponent() : common
                return (project.path, root.path)
            }
            let parent = root.deletingLastPathComponent()
            if parent.path == root.path { break }
            root = parent
        }
        return nil
    }

    private static func resolve(_ path: String, from base: URL) -> URL {
        (path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path))
            .standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func metadata(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 8193), data.count <= 8192 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct AgentDirectorySection: Identifiable {
    public let id: String
    public let worktreeName: String?
    public let agents: [Agent]
}

public enum AgentConversationOrder {
    public static func precedes(_ a: Agent, _ b: Agent) -> Bool {
        func priority(_ agent: Agent) -> Int {
            switch agent.state { case .waiting: return 0; case .working: return 1; default: return 2 }
        }
        if priority(a) != priority(b) { return priority(a) < priority(b) }
        return a.updatedAt == b.updatedAt ? a.id < b.id : a.updatedAt > b.updatedAt
    }
}

public struct AgentDirectoryProject: Identifiable {
    public let id: String
    public let name: String
    public let agents: [Agent]
    public let sections: [AgentDirectorySection]
    private let recentCutoff: Date
    private var hasActiveWork: Bool { agents.contains { $0.state == .waiting || $0.state == .working } }
    private func isInFocus(_ agent: Agent) -> Bool {
        agent.state == .waiting || agent.state == .working || agent.updatedAt >= recentCutoff
    }
    public var focusSections: [AgentDirectorySection] {
        hasActiveWork ? filteredSections(isInFocus) : sections
    }
    public var otherSections: [AgentDirectorySection] {
        hasActiveWork ? filteredSections { !isInFocus($0) } : []
    }
    public var otherCount: Int { otherSections.reduce(0) { $0 + $1.agents.count } }
    private func filteredSections(_ predicate: (Agent) -> Bool) -> [AgentDirectorySection] {
        sections.compactMap { section in
            let rows = section.agents.filter(predicate)
            return rows.isEmpty ? nil : AgentDirectorySection(id: section.id, worktreeName: section.worktreeName, agents: rows)
        }
    }

    public static func groups(for agents: [Agent], now: Date = Date()) -> [Self] {
        let locations = Dictionary(uniqueKeysWithValues: Set(agents.map(\.directory)).map { ($0, ProjectLocation(directory: $0)) })
        let ordered = AgentConversationOrder.precedes
        return Dictionary(grouping: agents, by: { locations[$0.directory]!.projectPath }).map { path, members in
            let sorted = members.sorted(by: ordered)
            let sections = Dictionary(grouping: sorted, by: { locations[$0.directory]!.worktreePath ?? path }).map { sectionPath, rows in
                AgentDirectorySection(id: sectionPath, worktreeName: locations[rows[0].directory]!.worktreeName, agents: rows.sorted(by: ordered))
            }.sorted { a, b in
                ordered(a.agents[0], b.agents[0])
            }
            return Self(id: path, name: locations[sorted[0].directory]!.projectName, agents: sorted, sections: sections, recentCutoff: now.addingTimeInterval(-86400))
        }.sorted { a, b in
            ordered(a.agents[0], b.agents[0])
        }
    }
}
