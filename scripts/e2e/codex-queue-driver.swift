import Foundation
import OneCore

/// Exercise the production queue transport against the isolated e2e terminal.
@main struct QueueDriver {
    static func main() {
        guard CommandLine.arguments.count == 5 else { exit(2) }
        let args = CommandLine.arguments
        let agent = Agent(id: "probe", name: "Probe", provider: "Codex", directory: args[2], sessionID: args[3], providerHome: args[1])
        let runner = AgentRunner()
        let finished = DispatchSemaphore(value: 0)
        var success = false
        runner.enqueue(agent: agent, prompt: args[4], image: nil) { result in
            switch result {
            case .success(let receipt): print(receipt); success = true
            case .failure(let error): print(error.localizedDescription)
            }
            finished.signal()
        }
        guard finished.wait(timeout: .now() + 40) == .success else { runner.stop(); exit(3) }
        exit(success ? 0 : 1)
    }
}
