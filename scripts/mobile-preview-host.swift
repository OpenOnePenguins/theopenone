import Foundation
import OneCore

/// Isolated end-to-end preview: production Store + bridge, deterministic provider fixture.
@main struct MobilePreviewHost {
    @MainActor static func main() async throws {
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let root = workspace.appendingPathComponent(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".build/mobile-preview")
        let port = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "8088"
        let responseDelay = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "0"
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cli = root.appendingPathComponent("fixture-cli")
        try """
        #!/bin/sh
        printf '%s\\n' "$@" > mobile-arguments.txt
        printf '%s\\n' '{"type":"system","session_id":"open-one-mobile-sample"}' '{"type":"assistant","message":{"content":[{"type":"text","text":"Your message reached Open One on the Mac and continued this same session. This response comes from an isolated test provider; no external desktop app is involved."}]}}'
        """.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        let store = Store(root: root, demo: false, runnerExecutable: cli)
        store.remoteSource = "sample"
        store.setDiscoveryEnabled(false)
        store.utilities.includeNotes = false
        store.snapshot.agents = [Agent(id: "mobile-sample", name: "Open One", provider: "Claude", directory: root.path, state: .done,
            title: "Continue from your phone", messages: [Message(role: "user", text: "Can Open One continue this conversation on my phone?"), Message(role: "assistant", text: "Yes. Open One on your phone connects directly to Open One on your Mac. Your conversation stays in the same worktree.\n\nThis is an isolated sample conversation for testing.")], sessionID: "open-one-mobile-sample", managed: true)]
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", workspace.appendingPathComponent("scripts/mobile-preview-server.py").path, "--root", root.path, "--port", port, "--command-response-delay", responseDelay]
        try process.run()
        defer { store.shutdown(); process.terminate() }
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("remote-connection.json").path) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        store.utilities.remoteRunning = true
        print("Open One isolated preview ready at http://127.0.0.1:\(port)")
        for _ in 0..<14400 {
            guard process.isRunning else { break }
            store.pollEvents(); store.pollRemoteCommands()
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }
}
