import AppKit
import OneCore

@MainActor func runApprovalTests(root: URL, check: (Bool, String) -> Void) async throws {
    let fixtureSource = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("scripts/approval-fixture.py")
    for provider in ["Claude", "Codex"] {
        for allow in [true, false] {
            let folder = root.appendingPathComponent("approval-\(provider)-\(allow)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let fixture = folder.appendingPathComponent("provider")
            try FileManager.default.copyItem(at: fixtureSource, to: fixture)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
            let store = Store(root: folder.appendingPathComponent("store"), runnerExecutable: fixture, useApprovalTransport: true)
            defer { store.shutdown() }
            store.createAgent(provider: provider, directory: folder.path, prompt: "test approval")
            guard let id = store.selected?.id else { check(false, "approval fixture creates a conversation"); continue }
            store.commitPending()
            for _ in 0..<300 {
                if store.approvals[id]?.isEmpty == false { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            guard let request = store.approvals[id]?.first else { check(false, "\(provider) exposes an approval through Store and real transport"); continue }
            let receipt = folder.appendingPathComponent("approval-receipt.json")
            check(store.agent(for: id)?.state == .waiting && !FileManager.default.fileExists(atPath: receipt.path), "\(provider) waits without executing or inventing approval")
            check(request.details.contains("printf fixture") && request.allowEnabled, "\(provider) shows complete command details")
            store.setDraft("Keep my next message", for: "agent:" + id)
            store.stageApproval("stale", agentID: id, allow: true)
            check(store.pending == nil, "\(provider) rejects an unrelated approval ID")
            store.stage("yes", agentID: id)
            check(store.pending == nil, "\(provider) cannot approve through freeform chat")
            store.stageApproval(request.id, agentID: id, allow: allow); store.undo()
            try await Task.sleep(nanoseconds: 80_000_000)
            check(!FileManager.default.fileExists(atPath: receipt.path), "\(provider) Undo sends no permission response")
            store.stageApproval(request.id, agentID: id, allow: allow)
            store.selection = nil
            store.commitPending()
            for _ in 0..<300 {
                if store.agent(for: id)?.state == .done { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            check(store.agent(for: id)?.state == .done && store.approvals[id] == nil, "\(provider) resumes after explicit \(allow ? "approval" : "denial")")
            let response = try String(contentsOf: receipt, encoding: .utf8)
            check(response.contains(provider == "Codex" ? (allow ? "accept" : "decline") : (allow ? "allow" : "deny")), "\(provider) delivers exact decision to original request")
            check(store.draft(for: "agent:" + id) == "Keep my next message", "\(provider) approval preserves unrelated draft and recipient selection")
            store.stageApproval(request.id, agentID: id, allow: true)
            check(store.pending == nil, "\(provider) completed approval cannot be replayed")
        }
        let folder = root.appendingPathComponent("approval-cancel-\(provider)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fixture = folder.appendingPathComponent("provider")
        try FileManager.default.copyItem(at: fixtureSource, to: fixture)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
        let store = Store(root: folder.appendingPathComponent("store"), runnerExecutable: fixture, useApprovalTransport: true)
        defer { store.shutdown() }
        store.createAgent(provider: provider, directory: folder.path, prompt: "cancel approval")
        let id = store.selected!.id; store.commitPending()
        for _ in 0..<300 {
            if store.approvals[id]?.isEmpty == false { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        if let request = store.approvals[id]?.first { store.stageApproval(request.id, agentID: id, allow: true) }
        else { check(false, "\(provider) cancellation fixture exposes pending command") }
        for _ in 0..<300 {
            if store.agent(for: id)?.state == .done { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        check(store.pending == nil && store.approvals[id] == nil && !FileManager.default.fileExists(atPath: folder.appendingPathComponent("approval-receipt.json").path), "\(provider) withdrawing request cancels staged approval without delivery")
    }
}
