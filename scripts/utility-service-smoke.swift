import Foundation
import AppKit

@main struct UtilityServiceSmoke {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("open-one-remote-smoke-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let utilities = Utilities(root: root)
        utilities.startRemote(lanAddress: "100.64.0.1")
        guard !utilities.remoteStarting, !utilities.remoteRunning, utilities.remoteError != nil else { fatalError("Tailscale address was accepted") }
        print("PASS: native service refuses Tailscale address")
        utilities.startRemote()
        for _ in 0..<50 {
            if utilities.remoteRunning { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard utilities.remoteRunning, let link = utilities.localRemoteURL, let token = link.fragment else { fatalError("Remote service did not become ready: \(utilities.remoteError ?? "unknown")") }
        guard utilities.lanAddresses.contains(utilities.remoteListenHost) else { fatalError("Bridge did not bind a current LAN interface") }
        print("PASS: native service starts bundled LAN bridge")
        let stateURL = URL(string: "http://\(utilities.remoteListenHost):\(utilities.remotePort)/api/state")!
        let (_, unauthorized) = try await URLSession.shared.data(from: stateURL)
        guard (unauthorized as? HTTPURLResponse)?.statusCode == 401 else { fatalError("Expected authentication") }
        print("PASS: native-started bridge requires authentication")
        var request = URLRequest(url: stateURL); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, authorized) = try await URLSession.shared.data(for: request)
        guard (authorized as? HTTPURLResponse)?.statusCode == 200, let value = try JSONSerialization.jsonObject(with: data) as? [String: Any], (value["agents"] as? [Any])?.isEmpty == true else { fatalError("Expected empty fixture Inbox") }
        print("PASS: authenticated native preview reads fixture Inbox")
        utilities.stopRemote()
        for _ in 0..<30 {
            if !FileManager.default.fileExists(atPath: root.appendingPathComponent("remote-connection.json").path) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard !utilities.remoteRunning, utilities.remoteURL == nil, !FileManager.default.fileExists(atPath: root.appendingPathComponent("remote-connection.json").path) else { fatalError("Remote stop left active connection") }
        print("PASS: stop revokes URL and removes active connection")
        utilities.startRemote()
        for _ in 0..<50 {
            if utilities.remoteRunning { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard utilities.remoteRunning, utilities.remoteURL?.fragment != token else { fatalError("Restart reused token") }
        print("PASS: restart rotates connection token")
        utilities.stopRemote(); utilities.shutdown()
        try await Task.sleep(nanoseconds: 300_000_000)
        print("6 service smoke checks passed")
    }
}
