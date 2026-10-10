import AppKit
import SwiftUI
import Combine
import QuartzCore
import OneCore

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        let activates = event.type == .leftMouseDown && (!isKeyWindow || !NSApp.isActive)
        let target = activates ? contentView?.hitTest(event.locationInWindow) : nil
        if activates { NSApp.activate(ignoringOtherApps: true); makeKey() }
        super.sendEvent(event)
        // Activation completes after dispatch. AppKit consumes that first click
        // in an inactive text editor, so finish its focus/caret placement next turn.
        if activates, let editor = target as? NSTextView, editor.isEditable {
            let point = editor.convert(event.locationInWindow, from: nil)
            DispatchQueue.main.async { [weak self, weak editor] in
                guard let self, self.isVisible, let editor, editor.window === self else { return }
                self.makeKey()
                self.makeFirstResponder(editor)
                editor.setSelectedRange(NSRange(location: editor.characterIndexForInsertion(at: point), length: 0))
            }
        } else if activates, let field = target as? NSTextField, field.isEditable {
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, self.isVisible, let field, field.window === self else { return }
                self.makeKey(); self.makeFirstResponder(field)
            }
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboarding: OnboardingWindowController?
    private var store: Store!
    private var toolbar: NSPanel!
    private var panel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private var keyMonitor: Any?
    private var modifierMonitor: Any?
    private var localModifierMonitor: Any?
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var conversations: [String: FloatingPanel] = [:]
    private var controlTap = ModifierDoubleTap()
    private var trackingMenus = 0
    private var tabSubscription: AnyCancellable?
    private var layoutSignature = ""
    private var positioned = false
    private var panelPresentationGeneration = 0
    private var hoverPresentedTab: String?
    private let capture = RegionCapture()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["doubleControlEnabled": true])
        NSApp.setActivationPolicy(.accessory)
        if let image = OpenOneBrand.image { NSApp.applicationIconImage = image }
        store = Store(discovery: SessionDiscovery())
        buildMenu()
        buildPanels()
        let setup = OnboardingModel(store: store)
        onboarding = OnboardingWindowController(model: setup) { [weak self] phone in
            self?.show(phone ? "Remote access" : "Inbox")
        }
        store.onOnboardingRequested = { [weak self] in self?.openOnboarding() }
        tabSubscription = store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updatePanelLayout() }
        }
        store.onResizeInbox = { [weak self] height in
            guard let self else { return }; self.resizePanel(width: self.panel.frame.width, height: max(520, height))
        }
        store.onDockToolbar = { [weak self] right in self?.dockToolbar(right: right) }
        store.onCapture = { [weak self] key in self?.captureRegion(composerKey: key) }
        store.onRevealInbox = { [weak self] in self?.show("Inbox") }
        store.onReflowPanel = { [weak self] in
            guard let self else { return }; self.layoutSignature = ""; self.show(self.store.tab)
        }
        store.onAttention = { [weak self] in self?.statusItem.button?.appearsDisabled = false }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) == nil }
            return consumed ? nil : event
        }
        modifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.modifierEvent(event) }
        }
        localModifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.modifierEvent(event) }; return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.controlTap.cancel(); self?.dismissPanelForClick(in: nil) }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.controlTap.cancel(); self?.dismissPanelForClick(in: event.window) }
            return event
        }
        NotificationCenter.default.addObserver(self, selector: #selector(saveWindowPosition(_:)), name: NSWindow.didMoveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reposition), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuOpened), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuClosed), name: NSMenu.didEndTrackingNotification, object: nil)
        toolbar.orderFrontRegardless()
        if setup.shouldPresent { onboarding?.present() }
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = OpenOneBrand.menuBarImage
        statusItem.button?.setAccessibilityLabel("Open One")
        statusItem.button?.toolTip = "Open One"
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Inbox", action: #selector(openInbox), keyEquivalent: "1").target = self
        menu.addItem(withTitle: "Talk", action: #selector(openTalk), keyEquivalent: "2").target = self
        menu.addItem(withTitle: "Remote access", action: #selector(openRemoteAccess), keyEquivalent: "").target = self
        menu.addItem(withTitle: "New agent…", action: #selector(newAgent), keyEquivalent: "n").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Connect agents…", action: #selector(openOnboarding), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit Open One", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); mainMenu.addItem(appItem)
        appItem.submenu = menu.copy() as? NSMenu
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = edit; mainMenu.addItem(editItem); NSApp.mainMenu = mainMenu
    }

    private func buildPanels() {
        toolbar = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 63, height: 483), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        toolbar.level = .floating; toolbar.isOpaque = false; toolbar.backgroundColor = .clear; toolbar.hasShadow = false
        toolbar.acceptsMouseMovedEvents = true
        toolbar.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; toolbar.hidesOnDeactivate = false
        toolbar.contentView = NSHostingView(rootView: ToolbarView(store: store,
            open: { [weak self] tab in self?.show(tab) },
            preview: { [weak self] tab in self?.previewPanel(tab) },
            toggle: { [weak self] tab in self?.togglePanel(tab) }))
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 517, height: 508), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        panel.title = "Open One — Inbox"
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = conversationBehavior
        panel.minSize = NSSize(width: 360, height: 155)
        panel.contentView = NSHostingView(rootView: MainView(store: store, close: { [weak self] in self?.hidePanel() }, popOut: { [weak self] id in self?.openConversation(id) }))
        reposition()
    }

    private func openConversation(_ id: String) {
        if let existing = conversations[id] {
            constrain(existing)
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 410), styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.title = store.snapshot.agents.first { $0.id == id }?.name ?? "Conversation"
        window.level = .floating; window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.isMovableByWindowBackground = true; window.hidesOnDeactivate = false
        window.collectionBehavior = conversationBehavior
        window.minSize = NSSize(width: 260, height: 280)
        window.contentView = NSHostingView(rootView: ConversationPanel(store: store, agentID: id) { [weak self, weak window] in
            window?.orderOut(nil); self?.conversations[id] = nil
        })
        let frame = NSScreen.main?.visibleFrame ?? panel.frame
        let offset = CGFloat(conversations.count % 5) * 30
        window.setFrameOrigin(NSPoint(x: max(frame.minX + 20, panel.frame.minX - 340 + offset), y: frame.midY - 205 - offset))
        constrain(window)
        conversations[id] = window
        window.makeKeyAndOrderFront(nil)
    }

    private func captureRegion(composerKey requestedKey: String? = nil) {
        guard !store.capturing else { return }
        let activeConversation = conversations.first { $0.value.isKeyWindow }
        let composerKey = store.captureComposerKey(requested: requestedKey ?? activeConversation.map { "agent:\($0.key)" })
        let conversation = conversations.first { "agent:\(store.canonicalAgentID($0.key))" == composerKey && $0.value.isKeyWindow }?.value
        let originalTab = store.tab
        store.capturing = true
        store.notice = nil
        // Do not hide/reopen the app just to discover that permission is missing.
        do { try capture.ensurePermission() }
        catch {
            store.notice = error.localizedDescription
            if let conversation { conversation.makeKeyAndOrderFront(nil) }
            else { show(["Inbox", "Talk"].contains(originalTab) ? originalTab : "Talk") }
            store.capturing = false
            return
        }
        NotificationCenter.default.post(name: .stopVoice, object: nil)
        // Invalidate a pending hover-dismiss animation before temporarily hiding.
        hoverPresentedTab = nil
        panelPresentationGeneration += 1
        let visible = ([toolbar!, panel!] + Array(conversations.values)).filter { $0.isVisible }
        visible.forEach { $0.orderOut(nil) }
        Task { [weak self] in
            guard let self else { return }
            do {
                // Let menu dismissal and orderOut reach the window server first.
                try await Task.sleep(nanoseconds: 200_000_000)
                if let image = try await self.capture.capture(to: self.store.root.appendingPathComponent("captures")) {
                    self.store.setAttachment(image, for: composerKey)
                } else {
                    self.store.notice = "Screenshot selection cancelled. Your existing draft and attachment are unchanged."
                }
            } catch { self.store.notice = error.localizedDescription }
            visible.forEach { $0.alphaValue = 1; $0.orderFront(nil) }
            if let conversation { NSApp.activate(ignoringOtherApps: true); conversation.makeKeyAndOrderFront(nil) }
            else {
                let destinationTab = composerKey == "talk" ? "Talk" : "Inbox"
                if visible.contains(where: { $0 === self.panel }), originalTab == destinationTab {
                    // Restore the same window without tab changes or entrance animation.
                    self.panel.ignoresMouseEvents = false
                    NSApp.activate(ignoringOtherApps: true); self.panel.makeKeyAndOrderFront(nil)
                } else { self.show(destinationTab) }
            }
            self.store.capturing = false
        }
    }

    private var conversationBehavior: NSWindow.CollectionBehavior {
        store.panelsOnAllSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.managed, .moveToActiveSpace, .fullScreenAuxiliary]
    }

    @objc private func saveWindowPosition(_ notification: Notification) {
        guard positioned, let window = notification.object as? NSWindow else { return }
        if window === toolbar { UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "toolbarFrame") }
        if window === panel { UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "panelFrame") }
    }

    @objc private func reposition() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        if !positioned {
            toolbar.setFrameOrigin(NSPoint(x: frame.minX, y: frame.midY + 180 - toolbar.frame.height))
            panel.setFrameOrigin(NSPoint(x: frame.minX + 73, y: max(frame.minY + 20, frame.midY + 165 - panel.frame.height)))
            if let saved = UserDefaults.standard.string(forKey: "toolbarFrame") { let previous = NSRectFromString(saved); toolbar.setFrameOrigin(NSPoint(x: previous.minX, y: previous.maxY - toolbar.frame.height)) }
            if let saved = UserDefaults.standard.string(forKey: "panelFrame") { panel.setFrameOrigin(NSRectFromString(saved).origin) }
            positioned = true
        }
        let toolbarScreen = bestScreen(for: toolbar)
        if let toolbarScreen {
            toolbar.setFrame(WindowPlacement.docked(toolbar.frame, to: toolbarScreen.visibleFrame), display: true)
            store.toolbarOnRight = toolbar.frame.midX >= toolbarScreen.visibleFrame.midX
        }
        constrain(panel)
        conversations.values.forEach { constrain($0) }
    }

    private func bestScreen(for window: NSWindow) -> NSScreen? {
        NSScreen.screens.max { left, right in
            let a = left.visibleFrame.intersection(window.frame)
            let b = right.visibleFrame.intersection(window.frame)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        } ?? NSScreen.main
    }

    private func dockToolbar(right: Bool?) {
        guard let screen = bestScreen(for: toolbar) else { return }
        let frame = screen.visibleFrame
        let docked = WindowPlacement.docked(toolbar.frame, to: frame, right: right)
        store.toolbarOnRight = docked.midX >= frame.midX
        let x = store.toolbarOnRight ? docked.minX - panel.frame.width - 10 : docked.maxX + 10
        let proposed = NSRect(x: x, y: docked.maxY - panel.frame.height, width: panel.frame.width, height: panel.frame.height)
        let adjacent = WindowPlacement.constrained(proposed, to: frame)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            toolbar.animator().setFrame(docked, display: true)
            panel.animator().setFrame(adjacent, display: true)
        }
        UserDefaults.standard.set(NSStringFromRect(docked), forKey: "toolbarFrame")
        UserDefaults.standard.set(NSStringFromRect(adjacent), forKey: "panelFrame")
    }
    private func constrain(_ window: NSWindow) {
        let screen = NSScreen.screens.max { left, right in
            let a = left.visibleFrame.intersection(window.frame)
            let b = right.visibleFrame.intersection(window.frame)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        } ?? NSScreen.main
        if let screen { window.setFrame(WindowPlacement.constrained(window.frame, to: screen.visibleFrame), display: true) }
    }
    private func show(_ tab: String, activate: Bool = true) {
        if activate { hoverPresentedTab = nil }
        panelPresentationGeneration += 1
        let wasVisible = panel.isVisible
        panel.ignoresMouseEvents = false
        store.tab = tab; store.panelVisible = true; updatePanelLayout()
        if !wasVisible, let screen = panel.screen ?? NSScreen.main {
            panel.setFrame(WindowPlacement.constrained(panel.frame, to: screen.visibleFrame), display: true)
        }
        if !wasVisible { panel.alphaValue = 0 }
        if activate {
            NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.08 : 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }
    private func hidePanel() {
        guard store.panelVisible else { return }
        hoverPresentedTab = nil
        store.panelVisible = false
        panel.ignoresMouseEvents = true
        panelPresentationGeneration += 1
        let generation = panelPresentationGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.06 : 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, generation == self.panelPresentationGeneration, !self.store.panelVisible else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.panel.ignoresMouseEvents = false
            }
        }
    }

    private func previewPanel(_ tab: String) {
        guard trackingMenus == 0, NSApp.modalWindow == nil,
              !store.showNewAgent, !store.showSettings, !store.showTracking, panel.attachedSheet == nil,
              !store.capturing, !store.voiceRecording, !store.toolbarPointerDown else { return }
        guard !store.panelVisible || store.tab != tab else { return }
        hoverPresentedTab = tab
        show(tab, activate: false)
    }

    private func togglePanel(_ tab: String) {
        guard !store.showNewAgent, !store.showSettings, !store.showTracking, panel.attachedSheet == nil else { return }
        if hoverPresentedTab == tab { show(tab) }
        else if store.panelVisible, store.tab == tab { hidePanel() }
        else { show(tab) }
    }

    private func dismissPanelForClick(in window: NSWindow?) {
        guard store.panelVisible, trackingMenus == 0, NSApp.modalWindow == nil,
              panel.attachedSheet == nil, !store.showSettings, !store.showTracking, !store.showNewAgent,
              !store.capturing, !store.voiceRecording else { return }
        // Toolbar buttons handle their own toggle. Sheets and panel content keep
        // their normal click behavior; clicks in another app pass through untouched.
        if window === panel || window === toolbar || window?.sheetParent === panel { return }
        // Nonactivating panels and synthesized input can arrive without a window.
        // Use screen coordinates as well so an inside click never dismisses them.
        let point = NSEvent.mouseLocation
        if panel.frame.contains(point) || toolbar.frame.contains(point) { return }
        hidePanel()
    }

    private func resizePanel(width: CGFloat, height: CGFloat, animated: Bool = false) {
        let old = panel.frame
        let proposed = NSRect(x: old.minX, y: old.maxY - height, width: width, height: height)
        let frame = (panel.screen ?? NSScreen.main)?.visibleFrame ?? proposed
        let target = WindowPlacement.constrained(proposed, to: frame)
        if animated, panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(target, display: true)
            }
        } else { panel.setFrame(target, display: true) }
    }

    private func updatePanelLayout() {
        guard panel != nil else { return }
        let behavior = conversationBehavior
        if panel.collectionBehavior != behavior { panel.collectionBehavior = behavior }
        for window in conversations.values where window.collectionBehavior != behavior { window.collectionBehavior = behavior }
        if UserDefaults.standard.bool(forKey: "panelsOnAllSpaces") != store.panelsOnAllSpaces {
            UserDefaults.standard.set(store.panelsOnAllSpaces, forKey: "panelsOnAllSpaces")
        }
        guard !store.showSettings, !store.showTracking, !store.showNewAgent, panel.attachedSheet == nil else { return }
        panel.title = "Open One — \(store.tab)"
        let agent = store.selected
        let notice = store.showingNotice && store.notice != nil
        let chatEmpty = (agent?.messages.isEmpty ?? true) && store.attachment == nil
        let signature = store.tab == "Inbox" ? "Inbox-list" : "\(store.tab)|\(agent?.id ?? "")|\(agent?.state.rawValue ?? "")|\(agent?.choices.count ?? 0)|\(notice)|\(chatEmpty)|\(store.routeDecision != nil)|\(store.tab == "Talk" && store.notice != nil)"
        guard signature != layoutSignature else { return }
        layoutSignature = signature
        panel.minSize = store.tab == "Inbox" ? NSSize(width: 600, height: 520) : NSSize(width: 360, height: 155)
        switch store.tab {
        case "Settings": resizePanel(width: 520, height: 620, animated: true)
        case "Notes": resizePanel(width: 580, height: 580, animated: true)
        case "Feedback": resizePanel(width: 520, height: 460, animated: true)
        case "Usage": resizePanel(width: 399, height: 460, animated: true)
        case "Remote access": resizePanel(width: 460, height: 540, animated: true)
        case "Agents": resizePanel(width: 399, height: 469, animated: true)
        case "Talk": resizePanel(width: 508, height: chatEmpty && store.notice == nil ? 420 : 600, animated: true)
        default:
            resizePanel(width: 920, height: 680, animated: true)
        }
    }

    @objc private func openInbox() { show("Inbox") }
    @objc private func openTalk() { show("Talk") }
    @objc private func openRemoteAccess() { show("Remote access") }
    @objc private func newAgent() { store.forkPrompt = store.draft; show("Inbox"); store.showNewAgent = true }
    @objc private func openOnboarding() { onboarding?.model.reopen(); onboarding?.present(); Task { await onboarding?.model.refresh() } }
    @objc private func settings() { show("Inbox"); store.showSettings = true }
    @objc private func quit() { NSApp.terminate(nil) }

    private func modifierEvent(_ event: NSEvent) {
        guard UserDefaults.standard.bool(forKey: "doubleControlEnabled"), event.type == .flagsChanged else {
            controlTap.cancel(); return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if controlTap.update(pressed: flags.contains(.control), otherModifiers: !flags.subtracting(.control).isEmpty, at: event.timestamp) {
            show("Talk")
        }
    }

    @objc private func menuOpened() { trackingMenus += 1 }
    @objc private func menuClosed() { trackingMenus = max(0, trackingMenus - 1) }

    private func handle(_ event: NSEvent) -> NSEvent? {
        // Menus and sheets own Escape while they are presented.
        controlTap.cancel()
        guard trackingMenus == 0, NSApp.modalWindow == nil, NSApp.keyWindow?.attachedSheet == nil else { return event }
        if let (id, window) = conversations.first(where: { $0.value.isKeyWindow }), event.keyCode == 53 {
            if store.pending?.agentID == id { store.undo() } else { window.orderOut(nil) }
            return nil
        }
        guard panel.isKeyWindow, !store.showNewAgent, !store.showSettings, !store.showTracking else { return event }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.keyCode == 53 {
            if store.pending != nil { store.undo() }
            else { NotificationCenter.default.post(name: .stopVoice, object: nil); hidePanel() }
            return nil
        }
        if event.modifierFlags.contains(.command) {
            switch key {
            case "1": show("Inbox"); return nil
            case "2": show("Talk"); return nil
            case "n": newAgent(); return nil
            default: return event
            }
        }
        guard ["Inbox", "Talk", "Agents"].contains(store.tab) else { return event }
        guard !(panel.firstResponder is NSTextView), event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
        switch key {
        case "j" where store.tab == "Inbox":
            store.moveSelection(-1); return nil
        case "k" where store.tab == "Inbox":
            store.moveSelection(1); return nil
        case "e" where store.tab == "Inbox":
            store.clearInboxSelected(); return nil
        case "s" where store.tab != "Agents": store.onCapture?(store.composerKey); return nil
        case "v" where store.tab != "Agents": NotificationCenter.default.post(name: .startVoice, object: nil); return nil
        case " " where store.tab != "Agents": NotificationCenter.default.post(name: .focusComposer, object: nil); return nil
        default:
            if store.tab == "Inbox", let number = Int(key), let agent = store.selected, agent.state == .waiting, number >= 1, number <= agent.choices.count {
                store.stage(agent.choices[number - 1], choice: number - 1); return nil
            }
        }
        return event
    }

    func applicationWillTerminate(_ notification: Notification) {
        onboarding?.model.cancelVerification()
        store.shutdown()
        capture.cancel()
        for monitor in [keyMonitor, modifierMonitor, localModifierMonitor, outsideClickMonitor, localClickMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
    }
}

@main struct OpenOneMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
