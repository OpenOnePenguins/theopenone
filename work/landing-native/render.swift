import AppKit
import SwiftUI
import OneCore

@main struct RenderLanding {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("open-one-landing-\(UUID().uuidString)")
        let store = Store(root: root, demo: true)
        defer { store.shutdown(); try? FileManager.default.removeItem(at: root) }
        store.toolbarOnRight = true
        store.tab = "Inbox"
        store.inboxScope = .all
        store.selection = "demo-claude"
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        func render<V: View>(_ name: String, _ view: V, width: CGFloat, height: CGFloat) throws {
            let size = NSSize(width: width, height: height)
            let host = NSHostingView(rootView: view.frame(width:width,height:height).preferredColorScheme(.dark))
            let window = NSWindow(contentRect: NSRect(origin:.zero,size:size),styleMask:[.borderless],backing:.buffered,defer:false)
            window.isOpaque = false; window.backgroundColor = .clear
            window.contentView = host; host.frame = NSRect(origin:.zero,size:size)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until:Date().addingTimeInterval(0.2))
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in:host.bounds) else { throw CocoaError(.fileWriteUnknown) }
            host.cacheDisplay(in:host.bounds,to:bitmap)
            guard let png = bitmap.representation(using:.png,properties:[:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to:out.appendingPathComponent(name + ".png"))
            print("Rendered \(name), \(Int(width))x\(Int(height)) from native SwiftUI")
        }
        func inbox(_ name: String) throws { try render(name, MainView(store:store,close:{},popOut:{_ in}),width:920,height:680) }
        func toolbar(_ name: String, expanded: Bool) throws {
            setenv("OPEN_ONE_RENDER_EXPANDED", expanded ? "1" : "0", 1)
            try render(name, ToolbarView(store:store,open:{_ in},preview:{_ in},toggle:{_ in}),width:63,height:483)
        }
        try toolbar("toolbar-collapsed",expanded:false)
        try toolbar("toolbar-expanded",expanded:true)
        try inbox("inbox-question")
        store.stage("Three tiers",choice:0,agentID:"demo-claude")
        try inbox("inbox-pending")
        store.undo()
        if let i = store.snapshot.agents.firstIndex(where:{$0.id == "demo-claude"}) {
            store.snapshot.agents[i].messages.append(Message(role:"user",text:"Three tiers"))
            store.snapshot.agents[i].choices = []
            store.snapshot.agents[i].requestID = nil
            store.snapshot.agents[i].state = .working
        }
        try inbox("inbox-working")
        store.selection = "demo-codex"
        try inbox("inbox-codex")
        store.selection = "demo-claude"
        try toolbar("toolbar-working",expanded:false)
        if let i = store.snapshot.agents.firstIndex(where:{$0.id == "demo-claude"}) {
            store.snapshot.agents[i].messages.append(Message(role:"assistant",text:"The pricing page is ready.\n\nThree tiers, a highlighted recommended plan, and a responsive comparison. Ready for your review."))
            store.snapshot.agents[i].state = .done
        }
        try inbox("inbox-done")
        try toolbar("toolbar-done",expanded:false)
    }
}
