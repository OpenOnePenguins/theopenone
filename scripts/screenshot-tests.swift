import AppKit
import Foundation
import OneCore

@MainActor func runScreenshotTests(root: URL, check: (Bool, String) -> Void) async throws {
    let folder = root.appendingPathComponent("screenshots")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let image = folder.appendingPathComponent("fixture.png")
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    for x in 0..<64 { for y in 0..<32 { bitmap.setColor(NSColor(deviceRed: x < 32 ? 1 : 0, green: 0, blue: x < 32 ? 0 : 1, alpha: 1), atX: x, y: y) } }
    try bitmap.representation(using: .png, properties: [:])!.write(to: image)
    let captureCLI = folder.appendingPathComponent("capture")
    try "#!/bin/sh\nfor destination do :; done\ncp '\(image.path)' \"$destination\"\n".write(to: captureCLI, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: captureCLI.path)
    var allowed = false
    let capture = RegionCapture(executable: captureCLI, permissionGranted: { allowed }, requestPermission: { allowed = true })
    let captured = try await capture.capture(to: folder.appendingPathComponent("captures"))!
    check(NSImage(contentsOf: captured) != nil, "first permission grant continues directly into capture")

    var permissionRequests = 0
    let denied = RegionCapture(executable: captureCLI, permissionGranted: { false }, requestPermission: { permissionRequests += 1 })
    do { try denied.ensurePermission(); check(false, "permission can be checked before hiding the composer") }
    catch { check(error is CaptureError && permissionRequests == 1, "permission can be checked before hiding the composer") }
    let targetStore = Store(root: folder.appendingPathComponent("capture-target"))
    targetStore.snapshot.agents = [Agent(id: "inbox-chat", name: "Inbox chat"), Agent(id: "popout-chat", name: "Popout chat")]
    targetStore.selection = "inbox-chat"; targetStore.tab = "Inbox"
    let destination = targetStore.captureComposerKey()
    check(destination == "agent:inbox-chat" && targetStore.tab == "Inbox", "toolbar screenshot keeps Inbox destination without switching to Talk")
    targetStore.selection = "popout-chat"
    targetStore.setAttachment(captured, for: destination)
    check(targetStore.attachment(for: "agent:inbox-chat") == captured && targetStore.attachment(for: "talk") == nil,
          "capture attaches to original chat even when selection changes during capture")
    check(targetStore.captureComposerKey(requested: "agent:popout-chat") == "agent:popout-chat", "popout capture targets its explicit composer")
    targetStore.tab = "Talk"
    check(targetStore.captureComposerKey() == "talk", "Talk capture retains the shared Talk composer")
    targetStore.tab = "Agents"
    check(targetStore.captureComposerKey() == "talk" && targetStore.tab == "Agents", "toolbar capture outside a conversation chooses Talk without opening it before capture")
    let cancelledCLI = folder.appendingPathComponent("cancelled")
    try "#!/bin/sh\nexit 1\n".write(to: cancelledCLI, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cancelledCLI.path)
    let cancelledImage = try await RegionCapture(executable: cancelledCLI, permissionGranted: { true }).capture(to: folder)
    check(cancelledImage == nil && targetStore.attachment(for: destination) == captured, "cancelled selection does not discard the prior screenshot")
    targetStore.shutdown()

    let failing = folder.appendingPathComponent("failure")
    try "#!/bin/sh\necho 'could not create image from display' >&2\nexit 1\n".write(to: failing, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: failing.path)
    do {
        _ = try await RegionCapture(executable: failing, permissionGranted: { true }).capture(to: folder)
        check(false, "capture failure is not mistaken for Escape")
    } catch { check(error.localizedDescription.contains("could not create image"), "capture failure is not mistaken for Escape") }

    // Real Store -> undo window -> AgentRunner -> subprocess -> parsed response.
    // The subprocess checks actual image bytes, not just a path-shaped argument.
    let cli = folder.appendingPathComponent("agent")
    try """
    #!/usr/bin/env python3
    import sys,json,pathlib,base64
    args=sys.argv[1:]
    if '--input-format' in args:
        message=json.loads(sys.stdin.readline())
        blocks=message['message']['content']
        data=base64.b64decode(next(b['source']['data'] for b in blocks if b['type']=='image'))
        assert next(b['text'] for b in blocks if b['type']=='text')
        event={'type':'assistant','message':{'content':[{'type':'text','text':'Verified screenshot bytes'}]}}
    else:
        data=pathlib.Path(args[args.index('--image')+1]).read_bytes()
        event={'type':'item.completed','item':{'type':'agent_message','text':'Verified screenshot bytes'}}
    assert data.startswith(bytes([137,80,78,71,13,10,26,10]))
    assert int.from_bytes(data[16:20],'big')==64 and int.from_bytes(data[20:24],'big')==32
    print(json.dumps(event),flush=True)
    """.write(to: cli, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
    for provider in ["Codex", "Claude"] {
        let store = Store(root: folder.appendingPathComponent(provider), demo: false, runnerExecutable: cli)
        defer { store.shutdown() }
        store.snapshot.agents = [Agent(id: "target", name: "target", provider: provider, directory: folder.path, managed: true), Agent(id: "other", name: "other", provider: provider, directory: folder.path, managed: true)]
        store.selection = "other"; store.tab = "Talk"; store.draft = "Unrelated draft"
        store.setAttachment(captured, for: "agent:target")
        store.stage("", agentID: "target", composerKeyOverride: "agent:target")
        check(store.pending?.attachment == captured && store.pending?.agentID == "target", "\(provider) floating composer stages image-only message for its own recipient")
        store.undo()
        check(store.attachment(for: "agent:target") == captured, "\(provider) Undo preserves screenshot")
        store.stage("", agentID: "target", composerKeyOverride: "agent:target")
        store.commitPending()
        for _ in 0..<100 {
            if store.agent(for: "target")?.state == .done { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        check(store.agent(for: "target")?.messages.contains { $0.text == "Verified screenshot bytes" } == true, "\(provider) screenshot reaches subprocess and response returns to conversation")
        check(store.attachment(for: "agent:target") == nil && store.draft == "Unrelated draft", "\(provider) delivery clears only originating attachment")
        store.createAgent(provider: provider, directory: folder.path, prompt: "", image: captured)
        check(store.pending?.attachment == captured, "\(provider) new-agent flow retains screenshot")
        store.undo()
        check(store.attachment == captured, "\(provider) new-agent Undo retains screenshot for retry")
        store.attachment = folder.appendingPathComponent("missing.png")
        store.stage("Missing image")
        check(store.pending == nil && store.notice?.contains("missing or unreadable") == true, "\(provider) missing attachment cannot silently send text alone")
        store.attachment = captured
        store.stage("File removed during Undo")
        let saved = try Data(contentsOf: captured)
        try FileManager.default.removeItem(at: captured)
        store.commitPending()
        check(store.attachment == captured && store.selected?.state == .idle, "\(provider) unavailable image at delivery preserves draft")
        try saved.write(to: captured)
    }
}
