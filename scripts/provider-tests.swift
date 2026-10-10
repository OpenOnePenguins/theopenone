import Foundation
import OneCore

@MainActor func runProviderTests(root: URL, check: (Bool, String) -> Void) async throws {
    let home = root.appendingPathComponent("provider-home")
    for version in ["v9.0.0", "v22.3.0"] {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".nvm/versions/node/\(version)/bin"), withIntermediateDirectories: true)
    }
    let paths = ProviderTools.searchPaths(environment: ["PATH": ":relative:/fixture/bin:/fixture/bin"], home: home)
    check(!paths.contains("") && !paths.contains("relative") && paths.filter { $0 == "/fixture/bin" }.count == 1, "provider search rejects cwd-relative and duplicate paths")
    let versions = paths.filter { $0.contains(".nvm/versions") }
    check(versions.count == 2 && versions[0].contains("v22.3.0"), "GUI discovery includes numerically newest nvm runtime first")
    let bin = home.appendingPathComponent("custom/bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    let cli = bin.appendingPathComponent("codex")
    try "#!/bin/sh\nprintf '%s\\n' 'codex-cli fixture-1'\n".write(to: cli, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
    check(ProviderTools.resolve(provider: "Codex", environment: ["PATH": bin.path], home: home) == cli, "explicit absolute PATH takes precedence over fallback installations")
    check(ProviderTools.environment(for: cli, environment: ["PATH": "/usr/bin"], home: home)["PATH"]?.hasPrefix(bin.path + ":") == true, "managed CLI receives sibling runtime on PATH")
    let version = await ProviderTools.inspect(provider: "Codex", executableOverride: cli)
    check(version.version == "codex-cli fixture-1" && version.issue == nil, "version probe captures output without a model request")
    do {
        _ = try AgentRunner.arguments(agent: Agent(id: "invalid", name: "invalid", provider: "Other", directory: root.path), prompt: "test", image: nil)
        check(false, "unknown managed provider is rejected")
    } catch { check(true, "unknown managed provider is rejected") }
    let inherited = bin.appendingPathComponent("inherited-pipe")
    try "#!/bin/sh\n/bin/sleep 4 &\nprintf '%s\\n' '{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"done\"}}'\nexit 0\n".write(to: inherited, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: inherited.path)
    let started = Date()
    let finished: Int32 = await withCheckedContinuation { continuation in
        AgentRunner(executableOverride: inherited).start(agent: Agent(id: "inherited", name: "inherited", provider: "Codex", directory: root.path), prompt: "test", image: nil) {
            if case .finished(let code) = $0 { continuation.resume(returning: code) }
        }
    }
    check(finished == 0 && Date().timeIntervalSince(started) < 3, "CLI completion does not wait on inherited descendant stdout")
    let hanging = bin.appendingPathComponent("hanging")
    try "#!/bin/sh\nexec /bin/sleep 30\n".write(to: hanging, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hanging.path)
    let timedOut = await ProviderTools.inspect(provider: "Codex", executableOverride: hanging, timeout: 0.1)
    check(timedOut.issue == "Version check timed out.", "version discovery has a bounded deadline")
}
