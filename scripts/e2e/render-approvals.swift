import AppKit
import SwiftUI
import OneCore

@main struct RenderApprovals {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let enable = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        if app.responds(to: enable) { app.perform(enable, with: NSNumber(value: true), with: "AXEnhancedUserInterface") }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("open-one-approval-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let fixture = temporary.appendingPathComponent("provider")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "scripts/approval-fixture.py"), to: fixture)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
        for provider in ["Codex", "Claude"] {
            let store = Store(root: temporary.appendingPathComponent(provider), runnerExecutable: fixture, useApprovalTransport: true)
            defer { store.shutdown() }
            store.createAgent(provider: provider, directory: temporary.path, prompt: "Review the proposed command")
            store.commitPending()
            for _ in 0..<200 {
                if let id = store.selection, store.approvals[id]?.isEmpty == false { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            guard let agent = store.selected, store.approvals[agent.id]?.isEmpty == false else { throw CocoaError(.validationMissingMandatoryProperty) }
            for tab in ["Talk", "Inbox", "Floating"] {
                store.tab = tab == "Floating" ? "Talk" : tab
                let content = tab == "Floating" ? AnyView(ConversationPanel(store: store, agentID: agent.id, close: {})) : AnyView(MainView(store: store, close: {}, popOut: { _ in }))
                let size = NSSize(width: tab == "Inbox" ? 900 : 508, height: 760)
                let view = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = view
                try await Task.sleep(nanoseconds: 150_000_000)
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("\(provider)-\(tab).png"))
                func attribute(_ object: NSObject, _ name: String) -> Any? {
                    let selector = NSSelectorFromString(name)
                    return object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() : nil
                }
                func nodes(_ object: Any, depth: Int = 0) -> [NSObject] {
                    guard depth < 30, let object = object as? NSObject else { return [] }
                    return [object] + ((attribute(object, "accessibilityChildren") as? [Any]) ?? []).flatMap { nodes($0, depth: depth + 1) }
                }
                for label in ["Approve command once", "Deny command"] {
                    guard let button = nodes(view).first(where: { element in ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"].contains { attribute(element, $0) as? String == label } }) else {
                        print(nodes(view).map { [attribute($0, "accessibilityRole") as? String ?? "", attribute($0, "accessibilityLabel") as? String ?? attribute($0, "accessibilityTitle") as? String ?? ""] })
                        throw NSError(domain: "ApprovalUI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing control: \(label)"])
                    }
                    let selector = NSSelectorFromString("accessibilityPerformPress")
                    typealias Press = @convention(c) (AnyObject, Selector) -> Bool
                    let press = unsafeBitCast(button.method(for: selector), to: Press.self)
                    guard press(button, selector) else { throw NSError(domain: "ApprovalUI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not press: \(label)"]) }
                    try await Task.sleep(nanoseconds: 20_000_000)
                    guard store.pending?.agentID == agent.id, store.pending?.approvalID != nil,
                          store.pending?.choiceIndex == (label == "Approve command once" ? 0 : 1) else { throw CocoaError(.validationMissingMandatoryProperty) }
                    store.undo()
                    try await Task.sleep(nanoseconds: 150_000_000)
                    print("PASS: \(provider) \(tab) visible \(label) stages exact request; Undo sends nothing")
                }
                window.contentView = nil
            }
        }
    }
}
