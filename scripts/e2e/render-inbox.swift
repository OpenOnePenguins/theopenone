import AppKit
import SwiftUI
import OneCore

/// Offscreen rendering only: no visible windows, user data, pointer or keyboard events.
@main struct RenderInbox {
    @MainActor static func main() throws {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let markdownPreview = CommandLine.arguments.contains("--markdown")
        if CommandLine.arguments.contains("--recommendation-flow") || markdownPreview {
            // Enable SwiftUI's lazy accessibility tree only in this fixture process.
            let enable = NSSelectorFromString("accessibilitySetValue:forAttribute:")
            if app.responds(to: enable) { app.perform(enable, with: NSNumber(value: true), with: "AXEnhancedUserInterface") }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("open-one-render-\(UUID().uuidString)")
        let savedDots = CommandLine.arguments.contains("--saved-dots")
        if savedDots {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for name in ["state.json", "preferences.json"] {
                let source = BridgePaths.root.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: source.path) { try FileManager.default.copyItem(at: source, to: root.appendingPathComponent(name)) }
            }
        }
        let store = Store(root: root, demo: !savedDots)
        if savedDots {
            print("Saved-state dots: \(store.toolbarIndicators.count); \(ToolbarStatus.activityLabel(for: store.toolbarIndicators)); review backlog: \(store.reviewAgents.count)")
        }
        defer { store.shutdown(); try? FileManager.default.removeItem(at: root) }
        store.tab = "Inbox"
        store.selection = store.inboxAgents.first?.id
        if CommandLine.arguments.contains("--resume") {
            let agent = Agent(id: "resume-preview", name: "Codex", provider: "Codex", directory: "/Projects/open-one",
                              state: .done, title: "Copy the One app faithfully", messages: [
                                Message(role: "user", text: "Can I continue this conversation in Open One?"),
                                Message(role: "assistant", text: "Yes. Type your next message below and press Send to continue with the original conversation history.")
                              ], sessionID: "preview-session", sourcePath: "/fixture/history.jsonl")
            store.snapshot.agents.append(agent)
            store.selection = agent.id; store.draft = "Continue improving the Inbox"
        }
        if CommandLine.arguments.contains("--running") { store.setInboxScope(.running) }
        if CommandLine.arguments.contains("--all") { store.setInboxScope(.all) }
        if CommandLine.arguments.contains("--reviewed") {
            store.markReviewed(store.inboxAgents.filter { $0.state == .done }.map(\.id))
        }
        let popoutPreview = CommandLine.arguments.contains("--popout")
        let emptyTalkPreview = CommandLine.arguments.contains("--empty-talk")
        let recommendationPreview = CommandLine.arguments.contains("--recommendation")
        let markdownTalk = CommandLine.arguments.contains("--markdown-talk")
        let talkPreview = CommandLine.arguments.contains("--talk") || recommendationPreview || markdownTalk
        let recipientPreview = CommandLine.arguments.contains("--recipients")
        if talkPreview || recipientPreview {
            store.tab = "Talk"
            store.selection = "demo-claude"
            store.snapshot.agents[0].directory = "/missing/orca/workspaces/shop/pricing-page"
            store.draft = "Use three tiers and highlight the Studio plan"
        }
        if emptyTalkPreview { store.tab = "Talk"; store.snapshot.agents = []; store.selection = nil }
        if recommendationPreview {
            store.selection = "demo-codex"
            store.draft = "Change the pricing tiers"
        }
        if CommandLine.arguments.contains("--ai-recommendation") {
            store.routeDecision = RoutingDecision(agentID: "demo-claude", reason: "This conversation is building the pricing page and is waiting for your choice of tiers.", confidence: 0.95)
        }
        let markdownCode = "let message = \"Hello, Open One\"\nprint(message)\n"
        let markdownSample = """
        ## Build complete

        **Readable replies** with *emphasis*, `inline code` and [documentation](https://example.com/docs).

        - Keep **conversation context** visible
          - Nested tasks stay grouped
        - [x] Render Markdown
        - [ ] Review the result

        3. Check the layout
        4. Continue the conversation

        > The agent's recommendation stays separate from your message.

        ```swift
        \(markdownCode)```

        | Feature | Status |
        | :--- | ---: |
        | Tables | **Ready** |
        | Code blocks | Copyable |

        ---

        Final paragraph. No Markdown markers around formatted text.
        """
        if markdownTalk {
            store.snapshot.agents[0].messages = [Message(role: "user", text: "Show a formatted reply"), Message(role: "assistant", text: "## Build complete\n\n**Markdown** is ready.\n\n- Lists retain their structure\n- Code keeps its formatting\n\n```swift\n\(markdownCode)```")]
            store.snapshot.agents[0].state = .done; store.draft = ""
        }
        let agentsPreview = CommandLine.arguments.contains("--agents")
        if CommandLine.arguments.contains("--writer-conflict") { store.notice = AgentRunner.writerBusyMessage }
        if agentsPreview {
            store.tab = "Agents"
            let directory = "/missing/orca/workspaces/the-open-one/zoanthid"
            store.snapshot.agents = [
                Agent(id: "running", name: "Codex", provider: "Codex", directory: directory, state: .working, title: "Copy the One app faithfully"),
                Agent(id: "new", name: "Codex", provider: "Codex", directory: directory, state: .done, title: "Respond to greeting"),
                Agent(id: "logo", name: "Codex", provider: "Codex", directory: directory, state: .working, title: "Design open one logo"),
                Agent(id: "old", name: "Codex", provider: "Codex", directory: directory, state: .done, title: "Older conversation", updatedAt: Date().addingTimeInterval(-172800))
            ]
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        if CommandLine.arguments.contains("--screenshot") {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            for x in 0..<64 { for y in 0..<32 { bitmap.setColor(NSColor(deviceRed: x < 32 ? 0 : 1, green: 0.4, blue: x < 32 ? 1 : 0, alpha: 1), atX: x, y: y) } }
            let image = output.appendingPathComponent("capture-fixture.png")
            try bitmap.representation(using: .png, properties: [:])!.write(to: image)
            store.setAttachment(image, for: store.captureComposerKey())
        }
        if CommandLine.arguments.contains("--branding") {
            guard OpenOneBrand.image != nil, OpenOneBrand.menuBarImage?.isTemplate == false else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            store.snapshot.agents = []; store.selection = nil; store.tab = "Talk"
            let view = NSHostingView(rootView: HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 20) {
                    HStack(spacing: 24) {
                        BrandLogo(size: 116).frame(width: 160, height: 150).background(.white, in: RoundedRectangle(cornerRadius: 16))
                        VStack(spacing: 0) {
                            ToolButton(store: store, icon: "bubble.left.and.bubble.right", label: "Chat with Open One", size: 32, branded: true) {}
                            ToolButton(store: store, icon: "mic", label: "Start recording", size: 31) {}
                            ToolButton(store: store, icon: "camera", label: "Attach a screenshot", size: 31) {}
                        }.frame(width: 40).padding(.vertical, 4).modifier(ToolbarCapsule())
                    }
                    HStack(spacing: 16) {
                        ForEach([false, true], id: \.self) { dark in
                            HStack(spacing: 12) {
                                Image(systemName: "wifi")
                                Image(nsImage: OpenOneBrand.menuBarImage!)
                                Image(systemName: "battery.100")
                            }.font(.system(size: 15)).foregroundStyle(dark ? .white : .black)
                                .padding(.horizontal, 14).frame(height: 32)
                                .background(Color(white: dark ? 0.08 : 0.94), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    MainView(store: store, close: {}, popOut: { _ in }).frame(width: 440, height: 240)
                }.frame(width: 440)
                SettingsView(store: store).frame(width: 440, height: 540)
            }.padding(24).background(Color(white: 0.12)).preferredColorScheme(.dark))
            let size = NSSize(width: 948, height: 588)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view; view.frame = NSRect(origin: .zero, size: size)
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: output.appendingPathComponent("branding.png"))
            print("Rendered branding: full-color asset, small sizes, Talk control, empty Talk and Settings")
            return
        }
        for (name, width) in (markdownPreview ? [("markdown", 460.0), ("markdown-narrow", 320.0)] : popoutPreview ? [("popout", 320.0)] : emptyTalkPreview ? [("empty-talk", 508.0)] : talkPreview ? [("talk", 508.0), ("talk-narrow", 399.0)] : recipientPreview ? [("recipients", 460.0)] : agentsPreview ? [("agents", 399.0)] : [("wide", 920.0), ("narrow", 600.0)]) {
            let size = NSSize(width: width, height: markdownPreview ? 870 : popoutPreview ? 410 : emptyTalkPreview ? 420 : talkPreview ? 600 : agentsPreview ? 469 : recipientPreview ? 510 : 680)
            var copiedMarkdownCode: String?
            let content: AnyView
            if markdownPreview {
                content = AnyView(MarkdownMessageView(markdownSample, copyCode: { copiedMarkdownCode = $0 })
                    .padding(20).frame(maxHeight: .infinity, alignment: .top).background(Color(white: 0.10)).preferredColorScheme(.dark))
            } else if popoutPreview {
                content = AnyView(ConversationPanel(store: store, agentID: "demo-claude", close: {}))
            } else if recipientPreview {
                content = AnyView(RecipientPicker(store: store).background(Color(white: 0.09)))
            } else if savedDots {
                content = AnyView(HStack(spacing: 60) {
                    AgentStatusDots(indicators: store.toolbarIndicators, compact: false).padding(12).frame(width: 60).background(.black, in: Capsule())
                    AgentStatusDots(indicators: store.toolbarIndicators, compact: true).padding(.vertical, 25).frame(width: 12).background(.black, in: Capsule())
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(white: 0.12)))
            } else if CommandLine.arguments.contains("--dots") {
                content = AnyView(HStack(alignment: .top, spacing: 36) {
                    ForEach([0, 4, 40], id: \.self) { count in
                        VStack(spacing: 24) {
                            Text("\(count) agents").foregroundStyle(.white)
                            AgentStatusDots(indicators: ToolbarStatus.activityIndicators(for: (0..<count).map { Agent(id: "agent-\($0)", name: "Agent", state: $0 % 3 == 0 ? .done : $0 % 3 == 1 ? .working : .waiting) }, reviewed: [:], completedUntil: Dictionary(uniqueKeysWithValues: (0..<count).filter { $0 % 3 == 0 }.map { ("agent-\($0)", Date().addingTimeInterval(20)) })), compact: false)
                                .padding(12).frame(width: 60).background(.black, in: Capsule())
                            AgentStatusDots(indicators: ToolbarStatus.activityIndicators(for: (0..<count).map { Agent(id: "agent-\($0)", name: "Agent", state: $0 % 3 == 0 ? .done : $0 % 3 == 1 ? .working : .waiting) }, reviewed: [:], completedUntil: Dictionary(uniqueKeysWithValues: (0..<count).filter { $0 % 3 == 0 }.map { ("agent-\($0)", Date().addingTimeInterval(20)) })), compact: true)
                                .padding(.vertical, 25).frame(width: 12).background(.black, in: Capsule())
                        }
                    }
                }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(white: 0.12)))
            } else { content = AnyView(MainView(store: store, close: {}, popOut: { _ in })) }
            let view = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            view.frame = NSRect(origin: .zero, size: size)
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: output.appendingPathComponent("inbox-\(name).png"))
            print("Rendered \(name): \(Int(view.bounds.width)) × \(Int(view.bounds.height))")
            if (CommandLine.arguments.contains("--recommendation-flow") && name == "talk") || markdownPreview {
                func attribute(_ element: NSObject, _ name: String) -> Any? {
                    let selector = NSSelectorFromString(name)
                    guard element.responds(to: selector) else { return nil }
                    return element.perform(selector)?.takeUnretainedValue()
                }
                func elements(_ object: Any, depth: Int = 0) -> [NSObject] {
                    guard depth < 30, let element = object as? NSObject else { return [] }
                    let children = attribute(element, "accessibilityChildren") as? [Any] ?? []
                    return [element] + children.flatMap { elements($0, depth: depth + 1) }
                }
                func press(_ label: String) throws {
                    let nodes = elements(view)
                    let matches = nodes.filter { element in ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"].contains { attribute(element, $0) as? String == label } }
                    let actionable = matches.first { ["AXButton", "AXLink"].contains(attribute($0, "accessibilityRole") as? String ?? "") } ?? matches.first
                    guard let button = actionable, button.responds(to: NSSelectorFromString("accessibilityPerformPress")) else {
                        print("Available controls: \(nodes.map { [NSStringFromClass(type(of: $0)), attribute($0, "accessibilityLabel") as? String ?? attribute($0, "accessibilityTitle") as? String ?? ""] })")
                        throw NSError(domain: "RecommendationUI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot press \(label)"])
                    }
                    let action = NSSelectorFromString("accessibilityPerformPress")
                    typealias Press = @convention(c) (AnyObject, Selector) -> Bool
                    let invoke = unsafeBitCast(button.method(for: action), to: Press.self)
                    guard invoke(button, action) else {
                        throw NSError(domain: "FixtureUI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Press failed for \(label), role \(attribute(button, "accessibilityRole") ?? "unknown")"])
                    }
                    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                }
                if markdownPreview {
                    try press("Copy code")
                    guard copiedMarkdownCode == markdownCode else { throw CocoaError(.validationMissingMandatoryProperty) }
                    print("PASS: visible Markdown Copy code preserves exact source without touching the user's clipboard")
                    let link = elements(view).first { attribute($0, "accessibilityRole") as? String == "AXLink" }
                    let target = link.flatMap { attribute($0, "accessibilityURL") as? URL }
                    guard target?.absoluteString == "https://example.com/docs" else {
                        throw NSError(domain: "MarkdownUI", code: 3, userInfo: [NSLocalizedDescriptionKey: "Native link exposes \(target?.absoluteString ?? "no URL")"])
                    }
                    print("PASS: native Markdown link exposes its expected destination; offscreen activation is not exercised")
                    continue
                }
                let draft = store.draft
                func hasReason() -> Bool {
                    elements(view).contains { element in
                        ["accessibilityLabel", "accessibilityValue"].contains { attribute(element, $0) as? String == store.recipientRecommendation.reason }
                    }
                }
                guard !hasReason() else { throw CocoaError(.validationMissingMandatoryProperty) }
                try press("Why this recipient?")
                guard hasReason() else { throw CocoaError(.validationMissingMandatoryProperty) }
                try press("Why this recipient?")
                guard !hasReason() else { throw CocoaError(.validationMissingMandatoryProperty) }
                print("PASS: Why expands the recommendation explanation and collapses it again")
                try press("Use this")
                guard store.selection == "demo-claude", store.draft == draft, store.pending == nil else { throw CocoaError(.validationMissingMandatoryProperty) }
                print("PASS: visible Use this selects matching conversation, preserves draft and does not send")
                try press("Ask AI to recommend")
                guard store.routeDecision?.agentID == "demo-claude", store.pending == nil else { throw CocoaError(.validationMissingMandatoryProperty) }
                print("PASS: visible AI action displays a recommendation (demo classifier; no model call)")
            }
        }
    }
}
