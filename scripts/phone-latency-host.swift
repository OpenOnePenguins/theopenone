import Foundation
import OneCore

/// Production desktop delivery with an isolated provider; never reads real chats.
@main struct PhoneLatencyHost {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let cli = root.appendingPathComponent("fixture-cli")
        try """
        #!/bin/sh
        printf '%s\\n' '{"type":"system","session_id":"phone-latency-fixture"}' '{"type":"assistant","message":{"content":[{"type":"text","text":"Isolated phone delivery accepted."}]}}'
        """.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        let store = Store(root: root, demo: false, runnerExecutable: cli)
        store.setDiscoveryEnabled(false)
        store.remoteSource = "sample"
        store.snapshot.agents = [Agent(id: "phone-latency", name: "Claude", provider: "Claude", directory: root.path,
            state: .done, title: "Phone latency fixture", sessionID: "phone-latency-fixture", managed: true)]
        store.utilities.remoteRunning = true
        defer { store.shutdown() }
        // The same 500 ms command polling cadence as the desktop app.
        for _ in 0..<240 {
            store.pollEvents(); store.pollRemoteCommands()
            try await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}
