import Foundation
import OneCore

/// Read the running Mac's state; use a private copy for the Store's tracking rules.
/// Never stage a message, run a provider, change tracking, or print conversation contents.
@main struct CheckPhoneParity {
    @MainActor static func main() throws {
        let source = BridgePaths.root
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("open-one-parity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporary) }
        for name in ["state.json", "preferences.json"] {
            try FileManager.default.copyItem(at: source.appendingPathComponent(name), to: temporary.appendingPathComponent(name))
        }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: temporary.appendingPathComponent("state.json")))
        let store = Store(root: temporary, demo: false)
        defer { store.shutdown() }
        store.snapshot = snapshot
        let expected = Dictionary(uniqueKeysWithValues: store.activeAgents.map { ($0.id, $0.remoteConversationKey) })
        let data = try Data(contentsOf: source.appendingPathComponent("remote-state.json"))
        let state = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let agents = state["agents"] as! [[String: Any]]
        let received = Dictionary(uniqueKeysWithValues: agents.compactMap { item -> (String, String)? in
            guard let id = item["id"] as? String, let key = item["conversationKey"] as? String else { return nil }
            return (id, key)
        })
        let passed = expected == received && state["source"] as? String == "desktop"
        let report: [String: Any] = ["macTrackedConversations": expected.count, "phoneConversations": received.count,
                                   "sameIDsAndSessionWorktreeKeys": passed, "source": state["source"] ?? "unknown",
                                   "realConversations": true, "readOnlyCheck": true]
        print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]), encoding: .utf8)!)
        if !passed { throw NSError(domain: "Phone list does not match this Mac", code: 1) }
    }
}
