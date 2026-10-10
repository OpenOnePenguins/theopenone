import AppKit
import ApplicationServices
import Foundation

struct Failure: Error { let message: String }
final class UITest {
    var app: AXUIElement!
    var process: Process!
    var checks: [[String: Any]] = []
    var expectedPointer: CGPoint?
    var inputInterrupted = false
    let folder: URL
    let dataRoot: URL
    init(_ folder: URL) { self.folder = folder; dataRoot = folder.appendingPathComponent("data") }
    func pause(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
    func value(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?; _ = AXUIElementCopyAttributeValue(e, key as CFString, &result); return result
    }
    func string(_ e: AXUIElement, _ key: String) -> String { value(e, key) as? String ?? "" }
    func children(_ e: AXUIElement) -> [AXUIElement] { value(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    func tree(_ e: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 22 else { return [] }; return [e] + children(e).flatMap { tree($0, depth: depth + 1) }
    }
    var windows: [AXUIElement] { guard let app else { return [] }; return value(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] }
    func rect(_ e: AXUIElement) -> CGRect {
        var point = CGPoint.zero, size = CGSize.zero
        if let v = value(e, kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgPoint, &point) }
        if let v = value(e, kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() { AXValueGetValue(v as! AXValue, .cgSize, &size) }
        return CGRect(origin: point, size: size)
    }
    var toolbar: AXUIElement? { windows.first { let r = rect($0); return r.width >= 60 && r.width <= 65 && r.height > 400 } }
    var panel: AXUIElement? { windows.first { string($0, kAXTitleAttribute).hasPrefix("Open One —") } }
    func find(_ label: String, within root: AXUIElement? = nil) -> AXUIElement? {
        (root.map { tree($0) } ?? windows.flatMap { tree($0) }).first { e in
            [kAXDescriptionAttribute, kAXTitleAttribute, "AXLabel"].contains { string(e, $0) == label }
        }
    }
    func hasText(_ text: String) -> Bool {
        windows.flatMap { tree($0) }.contains { string($0, kAXValueAttribute).contains(text) || string($0, kAXTitleAttribute).contains(text) }
    }
    func undoButton() -> AXUIElement? {
        windows.flatMap { tree($0) }.first { element in
            string(element, kAXRoleAttribute) == kAXButtonRole && [kAXTitleAttribute, kAXDescriptionAttribute].contains { string(element, $0).hasPrefix("Undo") }
        }
    }
    func wait(_ timeout: Double = 2, _ predicate: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        repeat { if expectedPointer != nil && !pointerStillAtTarget() { return false }; if predicate() { return true }; pause(0.04) } while Date() < end
        return predicate()
    }
    func check(_ name: String, _ predicate: @autoclosure () -> Bool) {
        let passed = predicate(); checks.append(["name": name, "passed": passed])
        print("\(passed ? "PASS" : "FAIL"): \(name)")
        if !passed {
            let labels = toolbar.map { tree($0).filter { string($0, kAXRoleAttribute) == kAXButtonRole }.map { string($0, kAXDescriptionAttribute) } } ?? []
            print("  toolbar=\(toolbar.map { rect($0).debugDescription } ?? "absent") controls=\(labels) panel=\(panel.map { string($0, kAXTitleAttribute) } ?? "none") pointer=\(CGEvent(source: nil)?.location ?? .zero)")
            if let point = CGEvent(source: nil)?.location, let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
                let atPointer = info.filter { d in guard let bounds = d[kCGWindowBounds as String] as? [String: Any], let r = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }; return r.contains(point) }.prefix(5).map { "\($0[kCGWindowOwnerName as String] ?? "?") pid=\($0[kCGWindowOwnerPID as String] ?? 0) layer=\($0[kCGWindowLayer as String] ?? 0) bounds=\($0[kCGWindowBounds as String] ?? "?")" }
                print("  windows under pointer: \(atPointer)")
            }

        }
    }
    func move(_ point: CGPoint) {
        guard !inputInterrupted else { return }
        expectedPointer = point
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        pause(0.03)
    }
    func pointerStillAtTarget() -> Bool {
        guard !inputInterrupted, let expectedPointer, let actual = CGEvent(source: nil)?.location else { return false }
        if hypot(actual.x - expectedPointer.x, actual.y - expectedPointer.y) > 4 { inputInterrupted = true; print("INPUT INTERRUPTED: pointer left test target; remaining input suppressed"); return false }
        return true
    }
    func center(_ e: AXUIElement) -> CGPoint { let r = rect(e); return CGPoint(x: r.midX, y: r.midY) }
    func click(_ point: CGPoint) {
        move(point)
        guard pointerStillAtTarget() else { return }
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        pause(0.02)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
    func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        guard !inputInterrupted else { return }
        guard wait(0.8, { NSWorkspace.shared.frontmostApplication?.processIdentifier == self.process.processIdentifier }) else {
            check("Keyboard input targets fixture app", false); return
        }
        for down in [true, false] { let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down); event?.flags = flags; event?.post(tap: .cghidEventTap) }
    }
    func type(_ text: String) {
        guard !inputInterrupted else { return }
        guard wait(0.8, { NSWorkspace.shared.frontmostApplication?.processIdentifier == self.process.processIdentifier }) else {
            check("Keyboard input targets fixture app", false); return
        }
        let units = Array(text.utf16)
        for down in [true, false] { let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down); event?.flags = []; units.withUnsafeBufferPointer { event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: $0.baseAddress) }; event?.post(tap: .cghidEventTap) }
    }
    var outside: CGPoint { CGPoint(x: CGDisplayBounds(CGMainDisplayID()).midX, y: 90) }
    func collapse() { move(outside); pause(0.45) }
    @discardableResult func reveal() -> Bool {
        guard let toolbar else { return false }
        if let tab = find("Show Open One controls", within: toolbar) { move(center(tab)) }
        else if let inbox = find("Inbox", within: toolbar) { move(center(inbox)) }
        let opened = wait {
            guard let button = self.find("Inbox", within: toolbar) else { return false }
            let r = self.rect(button), w = self.rect(toolbar)
            return r.width > 39 && r.minX >= w.minX && r.maxX <= w.maxX
        }
        if opened { pause(0.3) }
        return opened
    }
    func hover(_ label: String, tab: String) {
        guard let toolbar, let button = find(label, within: toolbar) else { check("\(label) control exists", false); return }
        move(center(button))
        check("Hover opens \(tab)", wait { self.panel.map { self.string($0, kAXTitleAttribute) == "Open One — \(tab)" } ?? false })
        pause(0.12)
    }
    func openBottom(_ label: String, tab: String) {
        collapse(); _ = reveal()
        if let toolbar, let more = find("Show more controls", within: toolbar) { move(center(more)) }
        _ = wait { self.find(label, within: self.toolbar) != nil }
        pause(0.35)
        hover(label, tab: tab)
    }
    func dismiss() {
        if let panel { click(CGPoint(x: rect(panel).midX, y: rect(panel).minY + 12)); pause(0.08); key(53) }
        _ = wait { self.panel == nil }; collapse()
    }
    func drag(_ start: CGPoint, _ end: CGPoint) {
        guard !inputInterrupted else { return }
        move(start)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)?.post(tap: .cghidEventTap)
        for step in 1...25 { let t = CGFloat(step) / 25; let p = CGPoint(x: start.x + (end.x-start.x)*t, y: start.y + (end.y-start.y)*t); CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap); pause(0.012) }
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)?.post(tap: .cghidEventTap)
        expectedPointer = end
        pause(0.4)
    }
    func seedDirectory() throws {
        let main = dataRoot.appendingPathComponent("projects/Zeta")
        let worktree = dataRoot.appendingPathComponent("checkouts/review")
        let admin = main.appendingPathComponent(".git/worktrees/review")
        for path in [admin, worktree.appendingPathComponent("src"), dataRoot.appendingPathComponent("events")] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        }
        try "../..".write(to: admin.appendingPathComponent("commondir"), atomically: true, encoding: .utf8)
        try "gitdir: \(admin.path)".write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        let now = Date().timeIntervalSinceReferenceDate
        func agent(_ id: String, _ directory: String, _ state: String, _ date: Double) -> [String: Any] {
            ["id": id, "name": id, "provider": "Codex", "directory": directory, "state": state, "title": "Fixture \(id)", "messages": [], "choices": [], "managed": false, "updatedAt": date, "archived": false]
        }
        let rows = [agent("recent", dataRoot.appendingPathComponent("Alpha").path, "idle", now), agent("done", main.path, "done", now-5), agent("working", worktree.path, "working", now-10), agent("waiting", worktree.appendingPathComponent("src").path, "waiting", now-100)]
        try JSONSerialization.data(withJSONObject: ["agents": rows, "processedEventIDs": []]).write(to: dataRoot.appendingPathComponent("state.json"))
        try Data(#"{"discoveryEnabled":false}"#.utf8).write(to: dataRoot.appendingPathComponent("preferences.json"))
    }
    func checkDirectory() throws {
        check("Hover reveals directory controls", reveal())
        hover("Your agents", tab: "Agents")
        guard let panel else { throw Failure(message: "No Agents panel") }
        move(CGPoint(x: rect(panel).midX, y: rect(panel).minY + 12)); pause(0.3)
        let labels = tree(panel).filter { string($0, kAXRoleAttribute) == kAXStaticTextRole }.map { string($0, kAXValueAttribute) }
        check("Worktree heading appears once for nested and root chats", labels.filter { $0 == "↳ review · worktree" }.count == 1)
        if let waiting = find("waiting"), let working = find("working"), let recent = find("recent") {
            check("Panel orders waiting before working", rect(waiting).minY < rect(working).minY)
            check("Inactive chats in busy project are collapsed", find("done") == nil)
            check("Attention project precedes alphabetically earlier recent project", rect(working).minY < rect(recent).minY)
            if let disclosure = find("Other conversations in Zeta") {
                AXUIElementPerformAction(disclosure, kAXPressAction as CFString)
                check("Older conversation remains accessible by expansion", wait { self.find("done") != nil })
            } else { check("Older conversation disclosure exists", false) }
            click(center(working))
            check("Click opens correct worktree conversation", wait { self.hasText("Fixture working") && self.panel.map { self.string($0, kAXTitleAttribute) == "Open One — Inbox" } == true })
            check("Conversation shows project and worktree context", hasText("Zeta · review"))
        } else { throw Failure(message: "Fixture conversation rows absent") }
        let event: [String: Any] = ["id":"new-attention", "agentID":"recent", "kind":"question", "text":"Fixture new attention", "requestID":"fixture-question", "choices":["Continue"]]
        try JSONSerialization.data(withJSONObject: event).write(to: dataRoot.appendingPathComponent("events/attention.json"), options: .atomic)
        pause(0.8)
        check("New attention keeps selected worktree conversation", hasText("Fixture working") && hasText("Zeta · review"))
        collapse(); _ = reveal(); hover("Your agents", tab: "Agents")
        if let recent = find("recent"), let waiting = find("waiting") {
            check("New waiting conversation moves project to top", rect(recent).minY < rect(waiting).minY)
        } else { check("Updated directory rows remain present", false) }
        dismiss()
    }
    func run() throws {
        check("Accessibility access available", AXIsProcessTrusted())
        guard AXIsProcessTrusted() else { throw Failure(message: "Accessibility access required") }
        print("Waiting for five seconds of desktop input inactivity (up to 45 seconds)…")
        let idleDeadline = Date().addingTimeInterval(45)
        var idle = false
        while Date() < idleDeadline {
            let quietFor = [CGEventType.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown].map {
                CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
            }.min() ?? 0
            if quietFor >= 5 { idle = true; break }
            pause(0.25)
        }
        guard idle else { throw Failure(message: "Desktop never became idle; no UI input sent") }
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        process = Process(); process.executableURL = fixture.appendingPathComponent("Contents/MacOS/OpenOne")
        let directoryOnly = CommandLine.arguments.contains("--directory-only")
        if directoryOnly { try seedDirectory() }
        process.arguments = directoryOnly ? [] : ["--demo"]
        var env = ProcessInfo.processInfo.environment; env["OPEN_ONE_HOME"] = dataRoot.path; process.environment = env
        process.standardOutput = FileHandle.nullDevice
        let traceURL = folder.appendingPathComponent("app.log")
        FileManager.default.createFile(atPath: traceURL.path, contents: nil)
        process.standardError = try FileHandle(forWritingTo: traceURL)
        try process.run(); app = AXUIElementCreateApplication(process.processIdentifier)
        defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
        check("Fixture starts", wait(8) { self.toolbar != nil })
        guard toolbar != nil else { throw Failure(message: "No fixture toolbar") }
        if CommandLine.arguments.contains("--activate") {
            NSRunningApplication(processIdentifier: process.processIdentifier)?.activate(options: [.activateIgnoringOtherApps])
            pause(0.3)
        }
        let otherCopies = NSWorkspace.shared.runningApplications.filter { running in
            running.processIdentifier != process.processIdentifier && ["local.openone.app", "com.one.app"].contains(running.bundleIdentifier ?? "") && !running.isHidden
        }
        for running in otherCopies { running.hide() }
        defer { for running in otherCopies { running.unhide() } }
        collapse()
        check("Default toolbar collapsed", find("Show Open One controls", within: toolbar) != nil)
        check("Default panel closed", panel == nil)
        if directoryOnly { try checkDirectory(); return }
        if !CommandLine.arguments.contains("--notes-only") {
        for pass in 1...3 {
            let revealed = reveal()
            check("Hover reveals controls, pass \(pass)", revealed)
            guard revealed else {
                if let tab = find("Show Open One controls", within: toolbar) { print("Collapsed target: \(rect(tab))") }
                throw Failure(message: inputInterrupted ? "Desktop input interrupted" : "Hover failed at actual AX target")
            }
            for (label, tab) in [("Inbox","Inbox"),("Your agents","Agents"),("Chat with Open One","Talk")] { hover(label, tab: tab); if inputInterrupted { throw Failure(message: "Desktop input interrupted") } }
            if let toolbar, let more = find("Show more controls", within: toolbar) { move(center(more)) }
            check("Bottom capsule expands, pass \(pass)", wait { self.find("Settings", within: self.toolbar) != nil })
            pause(0.35)
            for (label, tab) in [("Settings","Settings"),("Send feedback","Feedback"),("Notes","Notes"),("Remote access","Remote access"),("Usage","Usage")] { hover(label, tab: tab); if inputInterrupted { throw Failure(message: "Desktop input interrupted") } }
            if let panel { move(CGPoint(x: rect(panel).midX, y: rect(panel).minY + 50)); pause(0.4) }
            check("Panel stays open on entry, pass \(pass)", panel != nil)
            dismiss()
            check("Escape dismisses, pass \(pass)", panel == nil)
            check("Toolbar collapses, pass \(pass)", find("Show Open One controls", within: toolbar) != nil)
        }
        openBottom("Notes", tab: "Notes")
        if let toolbar, let notes = find("Notes", within: toolbar) {
            click(center(notes)); pause(0.2); check("First click focuses hover panel", panel != nil)
            click(center(notes)); pause(0.45); check("Second click closes without reopening", panel == nil)
        }
        collapse(); _ = reveal()
        if let toolbar, let inbox = find("Inbox", within: toolbar) { move(center(inbox)); pause(0.04); move(outside); pause(0.4) }
        check("Brief pass does not open panel", panel == nil)
        _ = reveal()
        for label in ["Start recording", "Attach a screenshot"] { if let toolbar, let target = find(label, within: toolbar) { move(center(target)); pause(0.35) } }
        check("Mic/camera hover does not start an action", panel == nil && find("Stop recording") == nil)
        collapse()
        if let toolbar {
            let start = CGPoint(x: rect(toolbar).minX + 6, y: rect(toolbar).minY + 180)
            drag(start, CGPoint(x: CGDisplayBounds(CGMainDisplayID()).maxX - 8, y: start.y))
            check("Drag docks on right edge", rect(toolbar).maxX > CGDisplayBounds(CGMainDisplayID()).maxX - 10)
            check("Drag does not open a panel", panel == nil)
            collapse(); check("Right-edge hover reveals controls", reveal()); hover("Inbox", tab: "Inbox"); dismiss()
            let r = rect(toolbar); drag(CGPoint(x: r.maxX - 6, y: r.minY + 180), CGPoint(x: 6, y: r.minY + 180))
            check("Drag returns to left edge", rect(toolbar).minX < 10)
        }
        }
        openBottom("Notes", tab: "Notes")
        if let editor = find("Working memory notes") {
            click(center(editor)); pause(0.2)
            if let focused = value(app, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() {
                let element = focused as! AXUIElement
                print("Notes focus: role=\(string(element, kAXRoleAttribute)) description=\(string(element, kAXDescriptionAttribute)) rect=\(rect(element))")
            }
            key(0, flags: .maskCommand); pause(0.08); type("E2E fixture notes — autosave")
            pause(0.3)
            print("Notes AX value after typing: \(string(editor, kAXValueAttribute).debugDescription)")
            check("Notes autosave", wait { (try? String(contentsOf: self.dataRoot.appendingPathComponent("notes.md"))) == "E2E fixture notes — autosave" })
            dismiss(); openBottom("Notes", tab: "Notes")
            check("Notes survive panel reopening", find("Working memory notes").map { string($0, kAXValueAttribute).contains("E2E fixture notes") } ?? false)
        } else { check("Notes editor accessible", false) }
        dismiss()
        if !CommandLine.arguments.contains("--notes-only") {
            openBottom("Send feedback", tab: "Feedback")
            if let editor = find("Feedback message") {
                click(center(editor)); pause(0.2); type("E2E feedback draft")
                check("Feedback draft saves from UI", wait { (try? String(contentsOf: self.dataRoot.appendingPathComponent("feedback-draft.md"))) == "E2E feedback draft" })
                check("Feedback sending disabled without destination", find("Open draft").map { (value($0, kAXEnabledAttribute) as? Bool) == false } ?? false)
                dismiss(); openBottom("Send feedback", tab: "Feedback")
                check("Feedback draft survives reopening", find("Feedback message").map { string($0, kAXValueAttribute) == "E2E feedback draft" } ?? false)
            } else { check("Feedback editor accessible", false) }
            dismiss(); _ = reveal(); hover("Inbox", tab: "Inbox")
            if let toolbar, let inbox = find("Inbox", within: toolbar) { click(center(inbox)); pause(0.2) }
            key(18)
            check("Numeric answer enters undo window", wait { self.undoButton() != nil })
            key(53)
            check("Escape undoes without closing Inbox", wait { self.undoButton() == nil && self.panel != nil })
            pause(2.1)
            check("Undone answer is not delivered", !hasText("Demo reply received"))
            key(18)
            check("Second answer enters undo window", wait { self.undoButton() != nil })
            check("Demo receives answer after delay", wait(6) { self.hasText("Demo reply received") })
            check("Completed card can be cleared", find("Clear from Inbox") != nil)
            key(14)
            check("E clears completed card", wait { !self.hasText("Demo reply received") })
            dismiss()
        }
        openBottom("Remote access", tab: "Remote access")
        if let start = find("Enable remote bridge") {
            AXUIElementPerformAction(start, kAXPressAction as CFString)
            check("Remote access starts from UI", wait(8) { self.find("Stop & revoke links") != nil })
            if let stop = find("Stop & revoke links") { AXUIElementPerformAction(stop, kAXPressAction as CFString) }
            check("Remote access stops from UI", wait { self.find("Enable remote bridge") != nil })
        } else { check("Remote enable button accessible", false) }
        dismiss()
        _ = reveal(); hover("Inbox", tab: "Inbox")
        if let toolbar { let r = rect(toolbar); click(CGPoint(x: r.maxX + 5, y: r.minY + 170)); pause(0.4) }
        check("Click-away closes panel", panel == nil)
        collapse()
    }
    func save() throws {
        let failed = checks.filter { ($0["passed"] as? Bool) != true }.count
        let result: [String: Any] = ["checks": checks, "passed": checks.count - failed, "failed": failed, "fixtureData": dataRoot.path, "date": ISO8601DateFormatter().string(from: Date())]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("results.json"))
        print("RESULT: \(checks.count - failed)/\(checks.count) passed; report \(folder.path)/results.json")
    }
}

setbuf(stdout, nil)
let folder = URL(fileURLWithPath: CommandLine.arguments[2]); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let test = UITest(folder)
do { try test.run() } catch { test.check("Runner completed: \(error)", false) }
try test.save()
exit(test.checks.allSatisfy { ($0["passed"] as? Bool) == true } ? 0 : 1)
