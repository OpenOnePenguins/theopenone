import AppKit
import SwiftUI
import OneCore

@main struct OnboardingTests {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var checks: [[String: Any]] = []
        func check(_ passed: Bool, _ name: String) throws {
            checks.append(["name":name,"passed":passed]); print("\(passed ? "PASS" : "FAIL"): \(name)")
            try JSONSerialization.data(withJSONObject: checks, options: [.prettyPrinted,.sortedKeys]).write(to: output.appendingPathComponent("checks.json"))
            if !passed { throw NSError(domain:"OnboardingE2E",code:1,userInfo:[NSLocalizedDescriptionKey:name]) }
        }
        func script(_ name: String, _ body: String) throws -> URL {
            let file = output.appendingPathComponent(name)
            try ("#!/bin/sh\n" + body + "\n").write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:file.path)
            return file
        }
        let codex = try script("codex", "if [ \"$1\" = '--version' ]; then echo 'codex fixture'; else echo 'Logged in using ChatGPT' >&2; fi")
        let claude = try script("claude", "if [ \"$1\" = '--version' ]; then echo 'claude fixture'; else echo '{\"loggedIn\":true,\"email\":\"fixture@example.invalid\"}'; fi")
        let signedOut = try script("signed-out", "if [ \"$1\" = '--version' ]; then echo fixture; elif [ \"$1\" = 'auth' ]; then echo '{\"loggedIn\":false}'; exit 1; else echo 'Not logged in' >&2; exit 1; fi")
        let malformed = try script("malformed", "echo 'unexpected output'")
        let timeout = try script("slow-auth", "if [ \"$1\" = '--version' ]; then echo fixture; else exec /bin/sleep 20; fi")
        let fixture = try script("runner", """
        if [ "$1" = 'exec' ]; then
          echo '{"type":"thread.started","thread_id":"11111111-1111-4111-8111-111111111111"}'
          echo '{"type":"item.completed","item":{"type":"agent_message","text":"Hello from Codex. Your conversation is connected."}}'
        else
          echo '{"type":"system","session_id":"22222222-2222-4222-8222-222222222222"}'
          echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Hello from Claude. Your conversation is connected."}]}}'
        fi
        """)
        func resolver(_ provider: String) -> URL? { provider == "Claude" ? claude : codex }
        func makeStore(_ name: String, runner: URL? = nil) -> Store { Store(root:output.appendingPathComponent(name),demo:false,runnerExecutable:runner ?? fixture) }
        func wait(_ model: OnboardingModel, timeout: TimeInterval = 12) async throws {
            let end = Date().addingTimeInterval(timeout)
            while model.verifying && Date() < end { try await Task.sleep(nanoseconds:50_000_000) }
            try check(!model.verifying,"connection check completes within its deadline")
        }
        func render(_ name: String, _ model: OnboardingModel) async throws {
            let host = NSHostingView(rootView:OnboardingView(model:model,later:{},finish:{_ in}))
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:640,height:610),styleMask:[.borderless],backing:.buffered,defer:false)
            window.contentView = host; host.frame = NSRect(x:0,y:0,width:640,height:610)
            try await Task.sleep(nanoseconds:200_000_000)
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds) else { throw CocoaError(.fileWriteUnknown) }
            host.cacheDisplay(in:host.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
        }
        let missing = await OnboardingProbe.inspect(provider:"Claude",executable:nil)
        try check(missing.state == .missing,"missing CLI provides installation recovery")
        for provider in OnboardingModel.providers {
            let loggedOut = await OnboardingProbe.inspect(provider:provider,executable:signedOut)
            try check(loggedOut.state == .needsSignIn,"\(provider) installed but signed out is not ready")
            let invalid = await OnboardingProbe.inspect(provider:provider,executable:malformed)
            try check(invalid.state == .failed,"\(provider) unknown status fails closed")
        }
        let slow = await OnboardingProbe.inspect(provider:"Codex",executable:timeout,timeout:0.15)
        try check(slow.state == .failed && slow.detail.contains("timed out"),"hanging auth command times out")
        let misleading = try script("signed-out-success", "echo 'Not logged in'")
        let misleadingStatus = await OnboardingProbe.inspect(provider:"Codex",executable:misleading)
        try check(misleadingStatus.state == .needsSignIn,"signed-out text cannot be mistaken for logged-in status")
        var rapidChecksPassed = true
        for _ in 0..<12 {
            let rapid = await OnboardingProbe.inspect(provider:"Codex",executable:codex)
            rapidChecksPassed = rapidChecksPassed && rapid.state == .ready
        }
        try check(rapidChecksPassed,"short-lived status processes retain all output at exit")
        let quoted = OnboardingProbe.loginScript(provider:"Claude",executable:URL(fileURLWithPath:"/tmp/a' b/claude"))
        try check(quoted.contains("'/tmp/a'\\'' b/claude' auth login"),"sign-in command safely quotes executable paths")

        let store = makeStore("happy")
        let model = OnboardingModel(store:store,resolve:resolver)
        try check(model.shouldPresent && !model.canContinue,"fresh launch presents setup and requires an agent choice")
        await model.refresh()
        try check(model.statuses.values.allSatisfy{$0.state == .ready},"both CLI sign-in formats recognized")
        try check(store.snapshot.agents.isEmpty,"installation and authentication checks never send a task")
        model.chooseProvider("Claude",selected:true);model.chooseProvider("Codex",selected:true)
        try check(model.canContinue,"selected authenticated agents can continue")
        try await render("01-connect",model)
        model.advance();try check(model.progress.step == 1,"connect leads to project selection")
        model.chooseProject(output.appendingPathComponent("nonexistent"));model.advance()
        try check(model.progress.step == 1 && !model.projectValid,"missing project blocks progression")
        let project = output.appendingPathComponent("project")
        try FileManager.default.createDirectory(at:project,withIntermediateDirectories:true)
        model.chooseProject(project);try await render("02-project",model);model.advance()
        try check(model.progress.step == 2 && !model.complete(),"setup cannot finish before a real response")
        model.error = nil;try await render("03-verify",model)
        model.verify();model.verify()
        try await wait(model)
        try check(model.allVerified && model.progress.step == 3,"real Store and runner receive both provider replies")
        try check(store.snapshot.agents.count == 2,"double-click verification does not duplicate requests")
        try check(store.snapshot.agents.allSatisfy{$0.directory == project.standardizedFileURL.resolvingSymlinksInPath().path && $0.managed && $0.state == .done},"first conversations use the chosen project and production Store")
        try check(store.snapshot.agents.first(where:{$0.provider == "Codex"})?.sessionID == "11111111-1111-4111-8111-111111111111","Codex preserves provider session identity")
        try check(store.snapshot.agents.first(where:{$0.provider == "Claude"})?.sessionID == "22222222-2222-4222-8222-222222222222","Claude preserves provider session identity")
        try await render("04-ready",model)
        let staleStore = makeStore("stale")
        try JSONEncoder().encode(model.progress).write(to:staleStore.root.appendingPathComponent("onboarding.json"))
        let stale = OnboardingModel(store:staleStore,resolve:resolver)
        try check(stale.progress.step == 0 && stale.shouldPresent,"missing verified conversations return to a recoverable setup step")
        staleStore.shutdown()
        try check(model.complete() && !model.shouldPresent,"completion is persisted only after verified responses")
        store.shutdown()
        let reopenedStore = makeStore("happy")
        let reopened = OnboardingModel(store:reopenedStore,resolve:resolver)
        try check(!reopened.shouldPresent && reopened.allVerified,"relaunch preserves verified setup and conversations")
        let persisted = try String(contentsOf:output.appendingPathComponent("happy/onboarding.json"))
        try check(!persisted.contains("fixture@example.invalid") && !persisted.contains("Logged in"),"setup persists no raw authentication details")
        reopened.reopen();await reopened.refresh()
        try check(reopened.progress.step == 0 && reopened.canContinue,"Settings can reopen setup and recheck agents")
        reopened.chooseProject(output.appendingPathComponent("different-project"))
        try check(!reopened.allVerified,"changing projects invalidates previous verification")
        reopenedStore.shutdown()

        let deferredStore = makeStore("deferred")
        let deferred = OnboardingModel(store:deferredStore,resolve:{_ in nil})
        await deferred.refresh();deferred.chooseProvider("Codex",selected:true);deferred.advance()
        try check(deferred.progress.step == 0 && !deferred.canContinue,"missing selected CLI cannot advance")
        try await render("05-missing-cli",deferred)
        try check(deferred.deferSetup(),"set up later saves progress")
        let later = OnboardingModel(store:deferredStore,resolve:resolver)
        try check(!later.shouldPresent && !later.progress.completed,"deferring does not claim a connection or nag on restart")
        later.reopen();try check(later.shouldPresent,"deferred setup is recoverable")
        deferredStore.shutdown()

        let corruptStore = makeStore("corrupt")
        try Data("{corrupt".utf8).write(to:corruptStore.root.appendingPathComponent("onboarding.json"))
        let corrupt = OnboardingModel(store:corruptStore,resolve:resolver)
        try check(corrupt.shouldPresent && corrupt.progress.step == 0 && corrupt.error != nil,"corrupt setup progress offers a fresh recoverable flow")
        corruptStore.shutdown()

        let failure = try script("runner-failure", "echo 'fixture auth expired' >&2; exit 1")
        let failedStore = makeStore("failed",runner:failure)
        let failed = OnboardingModel(store:failedStore,resolve:resolver)
        await failed.refresh();failed.chooseProvider("Codex",selected:true);failed.advance();failed.chooseProject(project);failed.advance();failed.verify();try await wait(failed)
        try check(!failed.allVerified && failed.error != nil && !failed.complete(),"provider failure does not mark setup complete")
        try await render("06-failed-reply",failed)
        failedStore.shutdown()

        let empty = try script("runner-empty", "exit 0")
        let emptyStore = makeStore("empty",runner:empty)
        let emptyModel = OnboardingModel(store:emptyStore,resolve:resolver)
        await emptyModel.refresh();emptyModel.chooseProvider("Codex",selected:true);emptyModel.advance();emptyModel.chooseProject(project);emptyModel.advance();emptyModel.verify();try await wait(emptyModel)
        try check(!emptyModel.allVerified && emptyModel.error?.contains("without a conversation response") == true,"exit success without a response is not verification")
        emptyStore.shutdown()

        let cancelStore = makeStore("cancel")
        let cancelled = OnboardingModel(store:cancelStore,resolve:resolver)
        await cancelled.refresh();cancelled.chooseProvider("Codex",selected:true);cancelled.advance();cancelled.chooseProject(project);cancelled.advance();cancelled.verify()
        try await Task.sleep(nanoseconds:100_000_000);cancelled.cancelVerification()
        try await Task.sleep(nanoseconds:2_300_000_000)
        try check(cancelStore.pending == nil && !cancelled.allVerified && !cancelled.verifying,"cancel during staged send prevents an agent request")
        cancelled.verify();try await wait(cancelled)
        try check(cancelled.allVerified,"cancelled setup can be retried explicitly")
        cancelStore.shutdown()

        let hangingRunner = try script("runner-hanging", "exec /bin/sleep 30")
        let hangingStore = makeStore("hanging",runner:hangingRunner)
        let hanging = OnboardingModel(store:hangingStore,resolve:resolver,verificationTimeout:2.5)
        await hanging.refresh();hanging.chooseProvider("Claude",selected:true);hanging.advance();hanging.chooseProject(project);hanging.advance();hanging.verify();try await wait(hanging)
        try check(hanging.error?.contains("didn’t respond in time") == true && !hanging.allVerified,"connection check timeout stops only its own runner")
        hangingStore.shutdown()
        print("\(checks.count) onboarding checks passed; renders and JSON report: \(output.path)")
    }
}
