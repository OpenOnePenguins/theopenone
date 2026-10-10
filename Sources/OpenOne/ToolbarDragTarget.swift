import AppKit
import SwiftUI
import OneCore

private protocol ToolbarPointerTarget: AnyObject {
    func synchronizePointer()
}

/// One passive event observer serves all visible toolbar targets.
private final class ToolbarPointerMonitor {
    static let shared = ToolbarPointerMonitor()
    private let targets = NSHashTable<NSView>.weakObjects()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    func add(_ view: NSView) {
        targets.add(view)
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                self?.synchronize(); return event
            }
        }
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.synchronize() }
        }
    }
    func remove(_ view: NSView) {
        targets.remove(view)
        guard targets.allObjects.isEmpty else { return }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil; globalMonitor = nil
    }
    private func synchronize() {
        for view in targets.allObjects { (view as? ToolbarPointerTarget)?.synchronizePointer() }
    }
}

/// Keep hover tracking fixed while the visible controls expand away from the edge.
struct ToolbarHoverArea: NSViewRepresentable {
    var enabled = true
    var observesPointer = false
    var moved: ((CGPoint?) -> Void)? = nil
    let changed: (Bool) -> Void
    final class HoverView: NSView, ToolbarPointerTarget {
        var enabled = true
        var changed: ((Bool) -> Void)?
        var moved: ((CGPoint?) -> Void)?
        private var area: NSTrackingArea?
        private var lastInside: Bool?
        private var lastLocation: CGPoint?
        var observesPointer = false { didSet { updatePointerMonitoring() } }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updatePointerMonitoring()
        }
        private func updatePointerMonitoring() {
            if observesPointer, window != nil { ToolbarPointerMonitor.shared.add(self) }
            else { ToolbarPointerMonitor.shared.remove(self) }
        }
        deinit { ToolbarPointerMonitor.shared.remove(self) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let next = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
            addTrackingArea(next)
            area = next
            synchronizePointer()
        }
        override func mouseEntered(with event: NSEvent) { synchronizePointer() }
        override func mouseExited(with event: NSEvent) { synchronizePointer() }
        override func mouseMoved(with event: NSEvent) { synchronizePointer() }
        func synchronizePointer() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                let point = self.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
                let inside = self.enabled && window.isVisible && !self.isHiddenOrHasHiddenAncestor && self.bounds.contains(point)

                if inside != self.lastInside {
                    self.lastInside = inside
                    self.changed?(inside)
                }
                if let moved = self.moved {
                    let location = inside ? CGPoint(x: point.x / max(1, self.bounds.width), y: 1 - point.y / max(1, self.bounds.height)) : nil
                    if location != self.lastLocation { self.lastLocation = location; moved(location) }
                }
            }
        }
    }
    func makeNSView(context: Context) -> HoverView { HoverView() }
    func updateNSView(_ view: HoverView, context: Context) {
        view.enabled = enabled
        view.observesPointer = observesPointer
        view.changed = changed
        view.moved = moved
        view.synchronizePointer()
    }
}

/// The whole control is the mouse target. Actions occur on mouse-up, never at drag start.
struct ToolbarDragTarget: NSViewRepresentable {
    let label: String
    let store: Store
    var enabled = true
    var hoverLabel: String? = nil
    var hoverAction: (() -> Void)? = nil
    var onPressChanged: ((Bool) -> Void)? = nil
    let action: () -> Void

    class TargetView: NSView, ToolbarPointerTarget {
        var action: (() -> Void)?
        var pressed: ((Bool) -> Void)?
        var dragEnded: (() -> Void)?
        var hoverLabel: String? { didSet { updatePointerMonitoring() } }
        private func updatePointerMonitoring() {
            if hoverLabel != nil, window != nil { ToolbarPointerMonitor.shared.add(self) }
            else { ToolbarPointerMonitor.shared.remove(self) }
        }
        deinit { ToolbarPointerMonitor.shared.remove(self) }
        func synchronizePointer() { synchronizeHoverPointer() }
        var hoverAction: (() -> Void)?
        var hoverOnRight = false
        var canShowHover: (() -> Bool)?
        private var hoverArea: NSTrackingArea?
        private var labelWork: DispatchWorkItem?
        private var panelWork: DispatchWorkItem?
        private var pointerInside = false
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverArea { removeTrackingArea(hoverArea) }
            guard hoverLabel != nil else { hoverArea = nil; dismissHoverLabel(); return }
            let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
            addTrackingArea(area); hoverArea = area
            synchronizeHoverPointer()
        }
        override func mouseEntered(with event: NSEvent) { synchronizeHoverPointer() }
        override func mouseExited(with event: NSEvent) { synchronizeHoverPointer() }
        func synchronizeHoverPointer() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // A held drag must not create a fresh hover entry when released.
                guard NSEvent.pressedMouseButtons == 0 else { self.dismissHoverLabel(); return }
                var inside = false
                if let window = self.window, window.isVisible, !self.isHiddenOrHasHiddenAncestor, self.hoverLabel != nil,
                   self.canShowHover?() == true {
                    let point = self.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
                    inside = self.bounds.contains(point)
                }
                guard inside != self.pointerInside else { return }
                self.pointerInside = inside
                if inside { self.beginHover() } else { self.dismissHoverLabel() }
            }
        }
        private func beginHover() {
            labelWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, let text = self.hoverLabel, let window = self.window, !self.isHidden, self.canShowHover?() == true else { return }
                let point = self.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
                guard self.bounds.contains(point) else { return }
                ToolbarHoverLabelPresenter.shared.show(text, from: self, onRight: self.hoverOnRight)
            }
            labelWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: work)
            panelWork?.cancel()
            let panelWork = DispatchWorkItem { [weak self] in
                guard let self, let window = self.window, !self.isHidden,
                      self.canShowHover?() == true,
                      NSEvent.pressedMouseButtons == 0 else { return }
                let point = self.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
                guard self.bounds.contains(point) else { return }
                self.hoverAction?()
            }
            self.panelWork = panelWork
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: panelWork)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updatePointerMonitoring()
            if window == nil { dismissHoverLabel(); pointerInside = false }
        }
        private func dismissHoverLabel() {
            labelWork?.cancel(); labelWork = nil
            panelWork?.cancel(); panelWork = nil
            ToolbarHoverLabelPresenter.shared.hide(from: self)
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func accessibilityPerformPress() -> Bool { action?(); return true }

        private func screenPoint(_ event: NSEvent) -> NSPoint {
            // Window-relative event coordinates can refer to a frame from before the last move.
            // Use the event's global coordinates so queued drag events cannot accumulate drift.
            if let location = event.cgEvent?.location {
                return NSPoint(x: location.x, y: CGDisplayBounds(CGMainDisplayID()).height - location.y)
            }
            return NSEvent.mouseLocation
        }

        override func mouseDown(with event: NSEvent) {
            dismissHoverLabel()
            guard let window else { return }
            let start = screenPoint(event)
            let origin = window.frame.origin
            var gesture = ToolbarGesture(start: start)
            var cancelled = false
            var releasedInside = false
            pressed?(true)
            defer { pressed?(false) }
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown], until: .distantFuture, inMode: .eventTracking, dequeue: true) {
                if next.type == .keyDown {
                    if next.keyCode == 53 { cancelled = true; window.setFrameOrigin(origin); break }
                    continue
                }
                let point = screenPoint(next)
                gesture.update(point)
                if gesture.dragging {
                    window.setFrameOrigin(NSPoint(x: origin.x + point.x - start.x, y: origin.y + point.y - start.y))
                }
                if next.type == .leftMouseUp {
                    let local = convert(window.convertPoint(fromScreen: point), from: nil)
                    releasedInside = bounds.contains(local)
                    break
                }
            }
            if cancelled { return }
            if gesture.dragging { dragEnded?() }
            else if gesture.shouldClick(releasedInside: releasedInside) { action?() }
        }
    }

    func makeNSView(context: Context) -> TargetView {
        let view = TargetView()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        return view
    }
    func updateNSView(_ view: TargetView, context: Context) {
        view.isHidden = !enabled
        if view.hoverLabel != hoverLabel {
            view.hoverLabel = hoverLabel
            view.updateTrackingAreas()
        }
        view.hoverOnRight = store.toolbarOnRight
        view.hoverAction = hoverAction
        view.canShowHover = { enabled && !store.toolbarPointerDown }
        view.setAccessibilityLabel(label)
        view.setAccessibilityHelp("Click to open. Drag to move the toolbar.")
        view.action = action
        view.pressed = { store.toolbarPointerDown = $0; onPressChanged?($0) }
        view.dragEnded = { store.onDockToolbar?(nil) }
        view.synchronizeHoverPointer()
    }
}

/// Keep the menu's native popup separate from its visual label, so AppKit cannot
/// compress the circular toolbar control into its standard popup-button bezel.
struct ToolbarMenuTarget: NSViewRepresentable {
    let store: Store
    @Binding var isPresented: Bool
    let makeMenu: () -> NSMenu

    func makeNSView(context: Context) -> ToolbarDragTarget.TargetView {
        let view = ToolbarDragTarget.TargetView()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        return view
    }

    func updateNSView(_ view: ToolbarDragTarget.TargetView, context: Context) {
        view.setAccessibilityLabel("More options")
        view.setAccessibilityHelp("Click for additional options. Drag to move the toolbar.")
        view.pressed = { store.toolbarPointerDown = $0 }
        view.dragEnded = { store.onDockToolbar?(nil) }
        view.action = { [weak view] in
            guard let view else { return }
            isPresented = true
            defer { isPresented = false }
            let menu = makeMenu()
            let x = store.toolbarOnRight ? -menu.size.width - 8 : view.bounds.maxX + 8
            menu.popUp(positioning: nil, at: NSPoint(x: x, y: view.bounds.maxY), in: view)
        }
    }
}

final class ToolbarActionMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { handler() }
}
