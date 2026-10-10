import Foundation
import OneCore

@MainActor func runProcessTests(root: URL, check: (Bool, String) -> Void) async throws {
    var errors: [String] = []
    AgentRunner.parse(Data(#"{"type":"turn.failed","error":{"message":"quota exhausted"}}"#.utf8)) {
        if case .error(let message) = $0 { errors.append(message) }
    }
    check(errors == ["quota exhausted"], "Codex nested turn failure is surfaced")
    errors = []
    AgentRunner.parse(Data(#"{"type":"result","is_error":true,"errors":["permission denied","retry later"]}"#.utf8)) {
        if case .error(let message) = $0 { errors.append(message) }
    }
    check(errors == ["permission denied\nretry later"], "Claude structured error details are surfaced")

    let broken = AgentRunner(executableOverride: root.appendingPathComponent("missing-cli"))
    let failure = await withCheckedContinuation { continuation in
        var didReportError = false
        broken.start(agent: Agent(id: "broken", name: "broken", provider: "Codex", directory: root.path, managed: true), prompt: "test", image: nil) {
            switch $0 {
            case .error: didReportError = true
            case .finished(let code): continuation.resume(returning: didReportError && code != 0)
            default: break
            }
        }
    }
    check(failure, "CLI launch failure reports error and completes lifecycle")

    let service = RoutingService(executableOverride: URL(fileURLWithPath: "/bin/sleep"))
    service.cancel()
    do {
        _ = try await service.suggest(text: "test", candidates: [], directory: root.appendingPathComponent("cancelled-router"))
        check(false, "cancelled routing cannot launch")
    } catch is CancellationError {
        check(true, "cancelled routing is cancellation rather than timeout")
    }

    var permissionRequested = false
    let capture = RegionCapture(permissionGranted: { false }, requestPermission: { permissionRequested = true })
    let task = Task { @MainActor in
        try await capture.capture(to: root.appendingPathComponent("cancelled-capture"))
    }
    task.cancel()
    do {
        _ = try await task.value
        check(false, "cancelled capture cannot request permission")
    } catch is CancellationError {
        check(!permissionRequested, "cancelled capture cannot request permission")
    }
}
