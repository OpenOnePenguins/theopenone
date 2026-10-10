import SwiftUI
import AppKit
import OneCore

extension AgentState {
    var color: Color {
        switch self {
        case .working: return Color(red: 1, green: 0.8, blue: 0.4)
        case .waiting: return Color(red: 1, green: 0.65, blue: 0.12)
        case .done: return Color(red: 0.25, green: 0.85, blue: 0.48)
        case .idle, .offline, .unknown: return Color(red: 152 / 255, green: 152 / 255, blue: 157 / 255)
        }
    }
}

struct Glass: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material; view.blendingMode = .behindWindow; view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { nsView.material = material }
}

struct PanelSurface: View {
    var dark: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if reduceTransparency { Color(white: dark ? 0.025 : 0.09) }
            else {
                Glass(material: .popover)
                Color.black.opacity(dark ? 0.62 : 0.22)
                LinearGradient(colors: [.white.opacity(0.075), .white.opacity(0.012), .black.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
}

struct StatusDot: View {
    let state: AgentState
    var body: some View {
        Circle().fill(state.color).frame(width: 9, height: 9).accessibilityLabel(state.label)
    }
}

/// Animates drawing only, keeping the toolbar's drag and hover geometry fixed.
private struct CompletionPulse: ViewModifier {
    var enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        let pulsing = enabled && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !pulsing)) { timeline in
            let phase = (1 - cos(timeline.date.timeIntervalSinceReferenceDate * .pi / 0.9)) / 2
            content
                .scaleEffect(pulsing ? 1 + 0.2 * phase : 1)
                .opacity(pulsing ? 1 - 0.35 * phase : 1)
        }
    }
}

// A native drag surface avoids SwiftUI scroll views and text selection consuming window drags.
struct PanelDragArea: NSViewRepresentable {
    var label = "Move panel"
    var onDragEnded: (() -> Void)?
    final class DragView: NSView {
        var dragEnded: (() -> Void)?
        var dragLabel = "Move panel"
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event); dragEnded?() }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func accessibilityLabel() -> String? { dragLabel }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) { nsView.dragEnded = onDragEnded; nsView.dragLabel = label }
}

struct KeyHint: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.48))
            .padding(.horizontal, 7).frame(minWidth: 23, minHeight: 22)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
            .accessibilityHidden(true)
    }
}

private struct ToolbarControlsVisibleKey: EnvironmentKey { static let defaultValue = true }
private extension EnvironmentValues {
    var toolbarControlsVisible: Bool {
        get { self[ToolbarControlsVisibleKey.self] }
        set { self[ToolbarControlsVisibleKey.self] = newValue }
    }
}

struct ToolButton: View {
    let store: Store
    let icon: String
    let label: String
    var active = false
    var size: CGFloat = 40
    var branded = false
    var hoverAction: (() -> Void)? = nil
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.toolbarControlsVisible) private var controlsVisible
    @State private var hovered = false
    @State private var pressed = false
    private var glyphSize: CGSize {
        switch icon {
        case "tray", "camera": return CGSize(width: 17, height: 15)
        case "mic": return CGSize(width: 12, height: 19)
        default: return CGSize(width: 18, height: 18)
        }
    }
    var body: some View {
        Group {
            if branded { BrandLogo(size: OpenOneBrand.toolbarSize).opacity(active ? 1 : 0.92) }
            else { Image(systemName: icon).resizable().scaledToFit().frame(width: glyphSize.width, height: glyphSize.height) }
        }
            .foregroundStyle(.white.opacity(active ? 1 : 0.92))
            .scaleEffect(reduceMotion ? 1 : pressed ? 0.96 : 1)
            .frame(width: 40, height: size)
            .background(.white.opacity(pressed ? 0.11 : hovered ? 0.035 : 0), in: Capsule())
            .animation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.24, dampingFraction: 0.8), value: hovered)
            .animation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.2, dampingFraction: 0.85), value: pressed)
            .accessibilityHidden(true)
            .overlay(ToolbarDragTarget(label: label, store: store, enabled: controlsVisible, hoverLabel: controlsVisible ? label : nil, hoverAction: hoverAction, onPressChanged: { pressed = $0 }, action: action))
            .onHover { hovered = $0 }
    }
}

struct ToolbarCapsule: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var hovered = false
    @State private var lightPoint = UnitPoint(x: 0.18, y: 0.08)
    func body(content: Content) -> some View {
        content.background {
            ZStack {
                if reduceTransparency { Color(white: 0.15) }
                else {
                    Glass().opacity(0.86)
                    LinearGradient(colors: [.white.opacity(0.13), .white.opacity(0.018), .black.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                RadialGradient(colors: [.white.opacity(hovered ? 0.12 : 0.04), .white.opacity(0.012), .clear], center: lightPoint, startRadius: 0, endRadius: 48)
            }
        }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(AngularGradient(colors: [.white.opacity(0.86), .white.opacity(0.13), .white.opacity(0.5), .white.opacity(0.12), .white.opacity(0.86)], center: lightPoint, startAngle: .degrees(-80), endAngle: .degrees(280)), lineWidth: 0.75).allowsHitTesting(false))
            .overlay(Capsule().inset(by: 1).stroke(LinearGradient(colors: [.white.opacity(0.27), .clear, .black.opacity(0.3)], startPoint: .top, endPoint: .bottom), lineWidth: 0.5).allowsHitTesting(false))
            .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.19), radius: 3, y: 2)
            .background(ToolbarHoverArea(moved: { location in
                if let location { lightPoint = UnitPoint(x: location.x, y: location.y) }
                else { lightPoint = UnitPoint(x: 0.18, y: 0.08) }
            }, changed: { hovered = $0 }))
            .animation(.easeOut(duration: 0.12), value: hovered)
            .animation(.easeOut(duration: 0.08), value: lightPoint)
    }
}

/// A tab growing out of the screen edge, including the concave shoulders.
private struct ToolbarEdgeTab: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: .zero)
        p.addCurve(to: CGPoint(x: w / 2, y: 9), control1: CGPoint(x: 0, y: 7), control2: CGPoint(x: 0, y: 7))
        p.addCurve(to: CGPoint(x: w, y: 23), control1: CGPoint(x: w, y: 10), control2: CGPoint(x: w, y: 14))
        p.addLine(to: CGPoint(x: w, y: h - 23))
        p.addCurve(to: CGPoint(x: w / 2, y: h - 9), control1: CGPoint(x: w, y: h - 14), control2: CGPoint(x: w, y: h - 10))
        p.addCurve(to: CGPoint(x: 0, y: h), control1: CGPoint(x: 0, y: h - 7), control2: CGPoint(x: 0, y: h - 7))
        p.closeSubpath()
        return p
    }
}

/// Both toolbar forms share the same per-conversation activity and review indicators.
struct AgentStatusDots: View {
    let indicators: [ToolbarIndicator]
    let compact: Bool
    var pulseCompletions = true
    private var columns: Int { compact ? (indicators.count > 16 ? 2 : 1) : (indicators.count > 32 ? 5 : indicators.count > 6 ? 4 : 1) }
    private var diameter: CGFloat { compact ? (columns == 2 ? 3.5 : 6.5) : (columns == 5 ? 6 : columns == 4 ? 7.5 : 10.5) }
    private var spacing: CGFloat { compact ? 5.5 : (columns > 1 ? 3 : 7) }
    var height: CGFloat {
        let rows = max(1, (indicators.count + columns - 1) / columns)
        return CGFloat(rows) * diameter + CGFloat(rows - 1) * spacing
    }
    var body: some View {
        Group {
            if indicators.isEmpty {
                Capsule().fill(.gray).frame(width: compact ? 5 : 10, height: 2).frame(height: height)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(diameter), spacing: compact || columns == 5 ? 2 : 3), count: columns), spacing: spacing) {
                    ForEach(indicators) { indicator in
                        Circle().fill(indicator.state.color).frame(width: diameter, height: diameter)
                            .modifier(CompletionPulse(enabled: pulseCompletions && indicator.state == .done))
                    }
                }
            }
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(ToolbarStatus.activityLabel(for: indicators))
    }
}

struct ToolbarView: View {
    @ObservedObject var store: Store
    var open: (String) -> Void
    var preview: (String) -> Void
    var toggle: (String) -> Void
    @State private var hovering = false
    @State private var pointerInside = false
    @State private var pointerInTab = false
    @State private var pointerInControls = false
    @State private var moreExpanded = false
    @State private var pointerInMore = false
    @State private var moreHoverTask: Task<Void, Never>?
    @State private var hoverTask: Task<Void, Never>?
    @State private var pinned = false
    @State private var menuVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var expanded: Bool { hovering || pinned || menuVisible || moreExpanded || store.voiceRecording }
    private var edgeAnchor: UnitPoint { store.toolbarOnRight ? .trailing : .leading }
    private var activityDots: AgentStatusDots { AgentStatusDots(indicators: store.toolbarIndicators, compact: false, pulseCompletions: expanded) }
    private var compactDots: AgentStatusDots { AgentStatusDots(indicators: store.toolbarIndicators, compact: true, pulseCompletions: !expanded) }
    private var controlsHeight: CGFloat { 160 + activityDots.height + 16 }
    private var controlsTop: CGFloat { max(8, (360 - controlsHeight) / 2 - 15) }
    private var compactHeight: CGFloat { compactDots.height + 50 }
    private var activityLabel: String { ToolbarStatus.activityLabel(for: store.toolbarIndicators) }
    var body: some View {
        ZStack(alignment: store.toolbarOnRight ? .topTrailing : .topLeading) {
                VStack(spacing: 9) {
                    activityDots.padding(.vertical, 8).frame(width: 40).accessibilityHidden(true)
                        .modifier(ToolbarCapsule())
                        .overlay(ToolbarDragTarget(label: "Your agents", store: store, enabled: expanded, hoverLabel: expanded ? activityLabel : nil, hoverAction: { preview("Agents") }) { toggle("Agents") })
                    VStack(spacing: 0) {
                        ToolButton(store: store, icon: "bubble.left.and.bubble.right", label: "Chat with Open One", size: 32, branded: true, hoverAction: { preview("Talk") }) { toggle("Talk") }
                        ToolButton(store: store, icon: store.voiceRecording ? "waveform" : "mic", label: store.voiceRecording ? "Stop recording" : "Start recording", size: 31) {
                            if !store.voiceRecording { open("Talk") }
                            NotificationCenter.default.post(name: store.voiceRecording ? .stopVoice : .startVoice, object: nil)
                        }.background(store.voiceRecording ? Color.red.opacity(0.8) : .clear, in: Circle())
                        ToolButton(store: store, icon: "camera", label: "Attach a screenshot", size: 31) { store.onCapture?(nil) }
                    }.frame(width: 40).padding(.vertical, 4).modifier(ToolbarCapsule())
                    moreControls
                }
                    .environment(\.toolbarControlsVisible, expanded)
                    .padding(store.toolbarOnRight ? .trailing : .leading, 8)
                    .padding(.top, controlsTop)
                    .opacity(expanded ? 1 : 0)
                    .scaleEffect(reduceMotion || expanded ? 1 : 0.3, anchor: edgeAnchor)
                    .offset(x: reduceMotion || expanded ? 0 : store.toolbarOnRight ? 12 : -12)
                    .allowsHitTesting(expanded).accessibilityHidden(!expanded)
                    compactDots.frame(width: 12, height: compactHeight)
                        .background(ToolbarEdgeTab().fill(.black.opacity(0.96)).scaleEffect(x: store.toolbarOnRight ? -1 : 1, y: 1))
                        .accessibilityHidden(true)
                        .overlay(ToolbarDragTarget(label: "Show Open One controls", store: store, hoverLabel: activityLabel) { revealControls() })
                        .padding(.top, (360 - compactHeight) / 2)
                        .opacity(expanded ? 0 : 1)
                        .scaleEffect(x: reduceMotion || !expanded ? 1 : 0.65, y: reduceMotion || !expanded ? 1 : 0.85, anchor: edgeAnchor)
                        .allowsHitTesting(!expanded).accessibilityHidden(expanded)
        }.frame(width: 63, height: 483, alignment: store.toolbarOnRight ? .topTrailing : .topLeading)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.26, dampingFraction: 0.90), value: expanded)
            .overlay(alignment: store.toolbarOnRight ? .topTrailing : .topLeading) {
                // Stable, tightly fitted tracking geometry is independent of
                // the visual spring, so animation cannot retrigger mouse exits.
                ZStack(alignment: store.toolbarOnRight ? .topTrailing : .topLeading) {
                    ToolbarHoverArea(observesPointer: true) { inside in
                        pointerInTab = inside
                        pointerInside = pointerInTab || pointerInControls
                        updateHover()
                    }.frame(width: 12, height: compactHeight)
                        .padding(.top, (360 - compactHeight) / 2)
                    ToolbarHoverArea(enabled: expanded, observesPointer: true) { inside in
                        pointerInControls = inside
                        pointerInside = pointerInTab || pointerInControls
                        updateHover()
                    }.frame(width: 40, height: controlsHeight + (moreExpanded ? 125.5 : 0))
                        .padding(.top, controlsTop)
                        .padding(store.toolbarOnRight ? .trailing : .leading, 8)
                    ToolbarHoverArea(enabled: expanded, observesPointer: true) { inside in
                        pointerInMore = inside
                        updateMoreHover()
                    }.frame(width: 40, height: moreExpanded ? 165.5 : 40)
                        .padding(.top, controlsTop + controlsHeight - 40)
                        .padding(store.toolbarOnRight ? .trailing : .leading, 8)
                }.transaction { $0.animation = nil }
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in menuVisible = true }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in menuVisible = false }
            .onChange(of: store.toolbarPointerDown) { down in
                // Exits during native drag tracking must be applied after release.
                if down { moreHoverTask?.cancel() }
                else { updateHover(); updateMoreHover() }
            }
            .onDisappear { hoverTask?.cancel(); moreHoverTask?.cancel() }.preferredColorScheme(.dark)
    }

    private var moreControls: some View {
        Group {
            if !moreExpanded {
            Image(systemName: "ellipsis").font(.system(size: 14))
                .frame(width: 40, height: 40).accessibilityHidden(true)
                .overlay(ToolbarDragTarget(label: "Show more controls", store: store, enabled: !moreExpanded) { moreExpanded = true })
            } else {
            VStack(spacing: 0) {
                ToolButton(store: store, icon: "gearshape", label: "Settings", size: 31.5, hoverAction: { preview("Settings") }) { toggle("Settings") }
                ToolButton(store: store, icon: "ladybug", label: "Send feedback", size: 31.5, hoverAction: { preview("Feedback") }) { toggle("Feedback") }
                ToolButton(store: store, icon: "note.text", label: "Notes", size: 31.5, hoverAction: { preview("Notes") }) { toggle("Notes") }
                ToolButton(store: store, icon: "antenna.radiowaves.left.and.right", label: "Remote access", size: 31.5, hoverAction: { preview("Remote access") }) { toggle("Remote access") }
                ToolButton(store: store, icon: "chart.bar", label: "Usage", size: 31.5, hoverAction: { preview("Usage") }) { toggle("Usage") }
            }.padding(.vertical, 4)
            }
        }.contextMenu {
            Button("New agent…") { open("Inbox"); store.newAgentDirectory = ""; store.showNewAgent = true }
            Button(pinned ? "Unpin toolbar" : "Keep toolbar expanded") { pinned.toggle() }
            Button("Move to left edge") { store.onDockToolbar?(false) }
            Button("Move to right edge") { store.onDockToolbar?(true) }
            Toggle("Show panels on all Spaces", isOn: $store.panelsOnAllSpaces)
        }.frame(width: 40, height: moreExpanded ? 165.5 : 40, alignment: .top)
            .clipped()
            .modifier(ToolbarCapsule())
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.22, dampingFraction: 0.90), value: moreExpanded)
            .onChange(of: menuVisible) { if !$0 { updateMoreHover() } }
    }

    private func updateMoreHover() {
        moreHoverTask?.cancel()
        guard !store.toolbarPointerDown, !menuVisible else { return }
        let inside = pointerInMore
        moreHoverTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: inside ? 80_000_000 : 160_000_000)
            guard !Task.isCancelled, !store.toolbarPointerDown, !menuVisible else { return }
            moreExpanded = inside
        }
    }

    private func updateHover() {
        hoverTask?.cancel()
        guard !store.toolbarPointerDown else { return }
        let inside = pointerInside
        hoverTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: inside ? 45_000_000 : 150_000_000)
            guard !Task.isCancelled, !store.toolbarPointerDown else { return }
            hovering = inside
        }
    }

    private func revealControls() {
        hoverTask?.cancel()
        hovering = true
        // Accessibility activation can occur without moving the pointer into the
        // toolbar. Give the next control time to be reached, then retract normally.
        hoverTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, !pointerInside, !store.toolbarPointerDown else { return }
            hovering = false
        }
    }

    private func toolbarMenu() -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, checked: Bool? = nil, action: @escaping () -> Void) {
            let entry = ToolbarActionMenuItem(title: title, handler: action)
            if let checked { entry.state = checked ? .on : .off }
            menu.addItem(entry)
        }
        item("New agent…") { open("Inbox"); store.newAgentDirectory = ""; store.showNewAgent = true }
        item("Settings…") { open("Inbox"); store.showSettings = true }
        item("Keep toolbar expanded", checked: pinned) { pinned.toggle() }
        item("Show panels on all Spaces", checked: store.panelsOnAllSpaces) { store.panelsOnAllSpaces.toggle() }
        item("Move to left edge") { store.onDockToolbar?(false) }
        item("Move to right edge") { store.onDockToolbar?(true) }
        menu.addItem(.separator())
        item("Quit Open One") { NSApp.terminate(nil) }
        return menu
    }
}

struct ProviderMark: View {
    let agent: Agent
    var body: some View {
        ProviderLogo(provider: agent.provider)
            .frame(width: 19, height: 22)
            .overlay(alignment: .bottomTrailing) { StatusDot(state: agent.state).overlay(Circle().stroke(.black, lineWidth: 1)).offset(x: 3, y: 1) }
    }
}

struct MainView: View {
    @ObservedObject var store: Store
    @StateObject private var speech = SpeechInput()
    @State private var dictationPrefix = ""
    @State private var dictationKey: String?
    @FocusState private var composerFocused: Bool
    @State private var resizeStart: CGFloat?
    @State private var choosingRecipient = false
    var close: () -> Void
    var popOut: (String) -> Void

    var body: some View {
        Group {
            if store.tab == "Settings" { SettingsView(store: store, close: close) }
            else if store.tab == "Notes" { NotesView(utilities: store.utilities, close: close) }
            else if store.tab == "Feedback" { FeedbackView(utilities: store.utilities, close: close) }
            else if store.tab == "Usage" { UsageView(utilities: store.utilities, close: close) }
            else if store.tab == "Remote access" { RemoteAccessView(utilities: store.utilities, close: close) }
            else if store.tab == "Agents" { AgentDirectoryView(store: store) }
            else if store.tab == "Talk" { chat }
            else { inbox }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if ["Inbox", "Talk"].contains(store.tab), let agent = store.selected { ApprovalView(store: store, agent: agent) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PanelSurface(dark: store.tab == "Inbox"))
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(LinearGradient(colors: [.white.opacity(0.52), .white.opacity(0.09), .white.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1).allowsHitTesting(false))
        .overlay(alignment: .bottomTrailing) { if store.tab == "Inbox" { resizeHandle } }
        .overlay(alignment: .top) {
            Capsule().fill(.white.opacity(0.22)).frame(width: 28, height: 3).frame(width: 90, height: 12)
                .overlay(PanelDragArea()).help("Drag to move panel")
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $store.showNewAgent, onDismiss: { store.forkSourceID = nil; store.forkPrompt = nil; store.onReflowPanel?() }) { NewAgentView(store: store) }
        .sheet(isPresented: $store.showSettings, onDismiss: { store.onReflowPanel?() }) { SettingsView(store: store) }
        .sheet(isPresented: $choosingRecipient, onDismiss: { store.onReflowPanel?() }) { RecipientPicker(store: store) }
        .sheet(isPresented: $store.showTracking, onDismiss: { store.onReflowPanel?() }) { TrackingView(store: store) }
        .onChange(of: store.showTracking) { if $0 { speech.stop() } }
        .onReceive(NotificationCenter.default.publisher(for: .startVoice)) { _ in toggleVoice() }
        .onReceive(NotificationCenter.default.publisher(for: .stopVoice)) { _ in speech.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .focusComposer)) { _ in composerFocused = true }
        .onChange(of: speech.transcript) { value in
            guard let key = dictationKey else { return }
            store.setDraft(dictationPrefix + (dictationPrefix.isEmpty || value.isEmpty ? "" : " ") + value, for: key)
        }
        .onChange(of: speech.recording) { store.voiceRecording = $0 }
        .onChange(of: speech.error) { if let error = $0 { store.notice = error } }
        .onChange(of: store.composerKey) { _ in speech.stop(); dictationKey = nil; composerFocused = false }
        .onChange(of: store.showNewAgent) { if $0 { speech.stop() } }
        .onChange(of: store.showSettings) { if $0 { speech.stop() } }
    }

    private var inbox: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Inbox").font(.system(size: 23, weight: .semibold))
                    Text("Questions and new results, ready to review").font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                }.frame(maxWidth: .infinity, alignment: .leading).overlay(PanelDragArea()).help("Drag to move Inbox")
                Button { store.showTracking = true } label: { Label("Worktrees", systemImage: "line.3.horizontal.decrease.circle") }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).accessibilityLabel("Tracked worktrees")
                Button { store.tab = "Talk" } label: { Label("Talk", systemImage: "bubble.left") }.buttonStyle(.plain).font(.system(size: 13, weight: .medium))
                Button { speech.stop(); close() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).frame(width: 32, height: 32).background(.white.opacity(0.08), in: Circle()) }
                    .buttonStyle(.plain).accessibilityLabel("Close Inbox")
            }.padding(.horizontal, 20).padding(.top, 19).padding(.bottom, 16)
            if let notice = store.notice {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle").foregroundStyle(.blue)
                    if notice == CaptureError.permission.localizedDescription { ScreenRecordingSettingsButton() }
                    ScrollView { Text(notice).font(.system(size: 14)).lineSpacing(3).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 62)
                    Button { store.notice = nil; speech.error = nil; store.showingNotice = false } label: { Image(systemName: "xmark").frame(width: 24, height: 24) }.buttonStyle(.plain).accessibilityLabel("Dismiss notice")
                }.padding(12).background(.white.opacity(0.06)).accessibilityElement(children: .contain)
            }
            Divider().overlay(.white.opacity(0.08))
            GeometryReader { geometry in
                if geometry.size.width >= 600 {
                    HStack(spacing: 0) {
                        InboxList(store: store, compact: geometry.size.width < 760).frame(width: min(310, geometry.size.width * 0.34))
                        Divider()
                        inboxDetail.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        InboxList(store: store, compact: true).frame(height: min(260, geometry.size.height * 0.40))
                        Divider()
                        inboxDetail.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            pendingBar.padding(.horizontal, store.pending == nil ? 0 : 16).padding(.vertical, store.pending == nil ? 0 : 10)
        }.background(Color(white: 0.065))
    }
    private var inboxDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let agent = store.selected, store.isTracked(agent), !agent.archived {
                Text(agent.displayTitle).font(.system(size: 21, weight: .semibold)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                taskCard(agent)
            } else { emptyInbox }
        }.padding(22)
    }

    @ViewBuilder private func taskCard(_ agent: Agent) -> some View {
        HStack(spacing: 11) {
            ProviderMark(agent: agent)
            Text("\(agent.state == .waiting ? "Waiting for your answer" : agent.state.label) · \(ProjectLocation(directory: agent.directory).displayName)")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.78)).lineLimit(2).help(agent.directory)
            Spacer(minLength: 0)
            Menu {
                if agent.state == .done { Button("Mark as needing review") { store.markNeedsReview(agent.id) } }
                Button("Open floating conversation") { popOut(agent.id) }
                Button("Talk to this agent") { store.tab = "Talk" }
                Button("Remove conversation from tracking") { store.trackConversation(agent.id, enabled: false) }
                Button("Remove worktree from tracking") { store.trackWorktree(agent.directory, enabled: false) }
                if agent.isObserved { Button("Fork in Open One") { store.prepareFork(agent) } }
                Button(agent.isHerdr ? "Interrupt agent" : "Stop agent") { store.stopSelected() }.disabled((!agent.managed && !agent.isHerdr) || agent.state != .working)
            } label: { Image(systemName: "ellipsis").frame(width: 22, height: 22) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Conversation actions")
        }
        LatestRequestView(agent: agent)
        if agent.isHerdr { HerdrTerminalView(store: store, agent: agent) }
        else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(history(agent)) { message in messageBubble(message, provider: agent.provider) }
                        if agent.state == .waiting {
                            VStack(alignment: .leading, spacing: 8) {
                                if let question = agent.messages.last { MessageByline(message: question, provider: agent.provider) }
                                MarkdownMessageView(agent.messages.last?.text ?? agent.title, fontSize: 17)
                            }.id("question")
                            if !agent.choices.isEmpty { choices(agent) }
                        }
                        if agent.state == .working {
                            HStack { ProgressView().controlSize(.small); Text("Working…").foregroundStyle(.white.opacity(0.75)) }.font(.system(size: 14)).padding(.vertical, 8)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.onAppear { proxy.scrollTo(agent.state == .waiting ? "question" : "bottom", anchor: agent.state == .waiting ? .top : .bottom) }
                    .onChange(of: agent.id) { _ in proxy.scrollTo(agent.state == .waiting ? "question" : "bottom", anchor: agent.state == .waiting ? .top : .bottom) }
                    .onChange(of: agent.messages.last?.text) { _ in proxy.scrollTo(agent.state == .waiting ? "question" : "bottom", anchor: agent.state == .waiting ? .top : .bottom) }
            }.frame(maxHeight: .infinity)
        }
        if agent.isObserved {
            HStack(spacing: 8) {
                Image(systemName: "clock").foregroundStyle(.gray)
                Text(agent.provider == "Codex" ? "Keep its terminal open. Messages queue in the existing Codex conversation while it is active." : "Close this session in its original app before continuing here.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Fork…") { store.prepareFork(agent) }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                    .help("Create a separate conversation from this history")
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Reply to \(agent.displayTitle) · \(ProjectLocation(directory: agent.directory).displayName)")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
            composer(placeholder: agent.state == .waiting ? "Type your answer…" : "Type a message…", shortcuts: false)
        }
        HStack {
            if store.demo { Text("Demo").font(.system(size: 11)).foregroundStyle(.gray) }
            Spacer()
            if agent.state == .done || agent.state == .idle || agent.state == .offline || agent.state == .unknown {
                Button { store.clearInboxSelected() } label: { HStack { Text(agent.state == .done ? "Mark reviewed" : "Archive"); KeyHint(text: "E") }.padding(.leading, 12).padding(4).background(.white.opacity(0.08), in: Capsule()) }.buttonStyle(.plain).accessibilityLabel(agent.state == .done ? "Mark result reviewed" : "Archive conversation")
            } else {
                Button { close() } label: { Text("Not now").foregroundStyle(.gray) }.buttonStyle(.plain)
            }
        }.font(.system(size: 13, weight: .medium))
    }
    private func history(_ agent: Agent) -> [Message] { agent.state == .waiting ? Array(agent.messages.dropLast()) : agent.messages }
    private func messageBubble(_ message: Message, provider: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MessageByline(message: message, provider: provider)
            MarkdownMessageView(message.text)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Color(white: message.role == "user" ? 0.15 : 0.105), in: RoundedRectangle(cornerRadius: 12))
    }
    private func choices(_ agent: Agent) -> some View {
        VStack(spacing: 7) {
            ForEach(Array(agent.choices.enumerated()), id: \.offset) { index, choice in
                Button { store.stage(choice, choice: index, agentID: agent.id) } label: {
                    HStack(spacing: 12) { Text(choice).font(.system(size: 15, weight: .medium)).multilineTextAlignment(.leading); Spacer(); KeyHint(text: "\(index + 1)") }
                        .padding(.horizontal, 16).padding(.vertical, 12).background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).disabled(store.pending != nil)
            }
        }
    }
    private var emptyInbox: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            BrandLogo(size: OpenOneBrand.emptyStateSize).accessibilityHidden(true)
            Text(store.inboxAgents.isEmpty ? "All caught up" : "Choose a conversation").font(.system(size: 24, weight: .semibold))
            Text(store.inboxAgents.isEmpty ? "Questions and finished work from your tracked agents will appear here." : "Select a conversation from the list to review its result or reply.").font(.system(size: 16)).foregroundStyle(.white.opacity(0.76)).lineSpacing(5)
            Button { store.newAgentDirectory = ""; store.showNewAgent = true } label: {
                HStack { Image(systemName: "plus"); Text("Start an agent"); Spacer() }.font(.system(size: 15, weight: .semibold)).padding(16).foregroundStyle(.black).background(.white, in: Capsule())
            }.buttonStyle(.plain)
            Button("Connect existing agents") { store.onOnboardingRequested?() }.buttonStyle(.plain).foregroundStyle(.gray)
            Spacer()
        }
    }
    private var chat: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Button { speech.stop(); choosingRecipient = true } label: {
                    HStack(alignment: .top, spacing: 10) {
                        if let agent = store.selected { ProviderLogo(provider: agent.provider, size: 23) }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.selected?.displayTitle ?? "Choose a conversation").font(.system(size: 17, weight: .semibold)).lineLimit(2)
                            if let agent = store.selected {
                                Text("\(agent.provider) · \(ProjectLocation(directory: agent.directory).displayName) · \(agent.state.label)")
                                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").font(.system(size: 12)).padding(.top, 5)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(speech.recording).accessibilityLabel("Choose recipient")
                Menu {
                    Button("Choose conversation…") { choosingRecipient = true }
                    if let agent = store.selected {
                        Button("Open conversation history") {
                            store.search = ""; store.setInboxScope(.all); store.selection = agent.id; store.onRevealInbox?()
                        }
                    }
                    Button("New agent…") { store.newAgentDirectory = ""; store.showNewAgent = true }
                } label: { Image(systemName: "ellipsis").frame(width: 22, height: 22) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(speech.recording).accessibilityLabel("Conversation actions")
            }
            if let agent = store.selected { LatestRequestView(agent: agent, compact: true) }
            if let agent = store.selected, !agent.messages.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(agent.messages) { message in messageBubble(message, provider: agent.provider) }
                            Color.clear.frame(height: 1).id("chat-bottom")
                        }
                    }.onAppear { proxy.scrollTo("chat-bottom", anchor: .bottom) }
                        .onChange(of: agent.messages.last?.text) { _ in proxy.scrollTo("chat-bottom", anchor: .bottom) }
                        .onChange(of: agent.id) { _ in proxy.scrollTo("chat-bottom", anchor: .bottom) }
                }
            } else {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 10) {
                        BrandLogo(size: OpenOneBrand.toolbarSize).accessibilityHidden(true)
                        Text("No messages yet").font(.system(size: 17, weight: .semibold))
                    }
                    Text("Say or type what you need. Choose the agent to help.").font(.system(size: 15)).foregroundStyle(.white.opacity(0.85))
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if let notice = store.notice {
                HStack { Text(notice).font(.system(size: 12)).foregroundStyle(.gray); if notice == CaptureError.permission.localizedDescription { ScreenRecordingSettingsButton() }; Spacer(); Button { store.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss notice") }
            }
            if store.selected.map({ store.approvals[$0.id]?.isEmpty != false }) ?? true {
                RecipientRecommendationView(store: store) { speech.stop(); choosingRecipient = true }
            }
            composer(placeholder: "Type a command…", shortcuts: false)
            pendingBar
        }.padding(19)
    }
    private func composer(placeholder: String, shortcuts: Bool) -> some View {
        VStack(spacing: 8) {
            if let attachment = store.attachment {
                AttachmentPreview(image: attachment) { store.attachment = nil }
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button("Capture screen region…") { store.onCapture?(store.composerKey) }.disabled(store.capturing)
                    Button("Attach image file…") { store.chooseImage() }
                } label: { HStack(spacing: 7) { Image(systemName: "camera").font(.system(size: 17)); if shortcuts { KeyHint(text: "S") } }.padding(.horizontal, 10).frame(height: 36).background(.white.opacity(0.07), in: Capsule()) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: shortcuts ? 62 : 36, height: 36).background(.white.opacity(0.07), in: Capsule()).accessibilityLabel("Attach screenshot")
                HStack(spacing: 5) {
                    TextField(placeholder, text: $store.draft, axis: .vertical).textFieldStyle(.plain).font(.system(size: 16)).lineLimit(1...4)
                        .focused($composerFocused).onSubmit { send() }.accessibilityLabel("Message")
                    Button { toggleVoice() } label: { Image(systemName: speech.recording ? "stop.circle.fill" : "mic").font(.system(size: 17)).foregroundStyle(speech.recording ? .red : .gray).frame(width: 26, height: 30) }
                        .buttonStyle(.plain).accessibilityLabel(speech.recording ? "Stop recording" : "Record a voice message")
                }.padding(.leading, 15).padding(.trailing, 7).padding(.vertical, 7).background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                Button { send() } label: {
                    HStack(spacing: 6) { Image(systemName: "arrow.up").font(.system(size: 18)); if shortcuts { KeyHint(text: "↵") } }
                        .padding(.horizontal, 11).frame(height: 36).foregroundStyle(canSend ? .black : .gray)
                        .background(canSend ? .white : .white.opacity(0.04), in: Capsule())
                }.buttonStyle(.plain).disabled(!canSend).help(sendHelp).accessibilityLabel("Send reply")
                    .accessibilityValue(store.selected?.displayTitle ?? "New agent")
            }
        }
    }
    @ViewBuilder private var pendingBar: some View {
        if let pending = store.pending {
            HStack {
                Text("Sending to \(store.snapshot.agents.first { $0.id == pending.agentID }?.displayTitle ?? "agent")…").lineLimit(2)
                Spacer()
                Button("Undo  esc") { store.undo() }.buttonStyle(.plain).fontWeight(.semibold)
            }.font(.system(size: 12)).padding(12).background(.white.opacity(0.08), in: Capsule())
        }
    }
    private var resizeHandle: some View {
        GeometryReader { geometry in
            Image(systemName: "line.3.diagonal").font(.system(size: 16)).foregroundStyle(.gray)
                .frame(width: 23, height: 23).contentShape(Rectangle())
                .position(x: geometry.size.width - 13, y: geometry.size.height - 13)
                .gesture(DragGesture().onChanged { value in
                    if resizeStart == nil { resizeStart = geometry.size.height }
                    store.onResizeInbox?((resizeStart ?? geometry.size.height) + value.translation.height)
                }.onEnded { _ in resizeStart = nil })
                .accessibilityLabel("Inbox size")
                .accessibilityAdjustableAction { direction in store.onResizeInbox?(geometry.size.height + (direction == .increment ? 40 : -40)) }
        }.allowsHitTesting(true)
    }
    private var canSend: Bool {
        guard (!store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.attachment != nil), store.pending == nil, !store.capturing else { return false }
        guard let agent = store.selected else { return true }
        return store.canSend(to: agent)
    }
    private var sendHelp: String {
        guard let agent = store.selected else { return "Start a new agent" }
        if store.approvals[agent.id]?.isEmpty == false { return "Review this command, then choose Approve once or Deny" }
        if agent.isHerdr && agent.state == .waiting { return "Answer the approval in its terminal" }
        if agent.canQueue { return "Send to \(agent.displayTitle) · Return" }
        if agent.state == .working { return "Wait for this agent to finish or stop it first" }
        if agent.isObserved { return agent.canResume ? "Continue \(agent.displayTitle) · Return" : "Finish or stop this session in its original app first" }
        return "Send to \(agent.displayTitle) · Return"
    }
    private func send() {
        guard canSend else { return }
        speech.stop()
        if store.selected == nil { store.showNewAgent = true }
        else { store.stage(store.draft) }
    }
    private func toggleVoice() {
        if speech.recording { speech.stop() }
        else { dictationKey = store.composerKey; dictationPrefix = store.draft; speech.start() }
    }
}

struct AgentDirectoryView: View {
    @ObservedObject var store: Store
    @State private var expandedProjects: Set<String> = []
    private var groups: [AgentDirectoryProject] { AgentDirectoryProject.groups(for: store.activeAgents) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Your agents").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { store.refreshDiscoveryIfNeeded(force: true) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(store.discovering || !store.discoveryEnabled || store.demo)
                    .help(store.discovering ? "Scanning conversations…" : "Refresh conversations")
                    .accessibilityLabel("Refresh conversations")
                Button("Tracked worktrees…") { store.showTracking = true }.buttonStyle(.plain).font(.system(size: 12))
            }.padding(17)
            if !store.reviewAgents.isEmpty || store.notice != nil {
                Button {
                    store.search = ""; store.setInboxScope(.review); store.showingNotice = false
                    store.onRevealInbox?()
                } label: {
                    HStack {
                        Text(store.reviewAgents.isEmpty ? "View notice" : "Needs review · \(store.reviewAgents.count)")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }.font(.system(size: 12, weight: .medium)).padding(10)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).padding(.horizontal, 17).padding(.bottom, 10)
            }
            Text("Amber: working · Orange: needs an answer · Green: just finished")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 17).padding(.bottom, 10)
            if !store.discoveryEnabled {
                Button("Enable local conversation discovery") { store.setDiscoveryEnabled(true) }
                    .font(.system(size: 12)).padding(.bottom, 10)
            }
            if let message = store.discoveryNotice {
                Text(message).font(.system(size: 11)).foregroundStyle(.orange).padding(.horizontal, 17).padding(.bottom, 10)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    if groups.isEmpty { Text("No agents yet").font(.system(size: 17, weight: .semibold)).padding(.vertical, 16) }
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(spacing: 8) {
                                Text(group.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.gray).lineLimit(1).help(group.id)
                                Menu {
                                    Button("Claude Code") { create("Claude", path: group.agents.first?.directory ?? group.id) }
                                    Button("Codex") { create("Codex", path: group.agents.first?.directory ?? group.id) }
                                } label: { Image(systemName: "plus").font(.system(size: 12)).frame(width: 19, height: 19) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("New agent in \(group.name)")
                                Spacer()
                            }
                            directorySections(group.focusSections)
                            if group.otherCount > 0 {
                                DisclosureGroup(isExpanded: Binding(get: { expandedProjects.contains(group.id) }, set: { value in
                                    if value { expandedProjects.insert(group.id) } else { expandedProjects.remove(group.id) }
                                })) {
                                    directorySections(group.otherSections)
                                } label: {
                                    Text("\(group.otherCount) older conversation\(group.otherCount == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(.gray)
                                }.accessibilityLabel("Older conversations in \(group.name)")
                            }
                        }
                    }
                }.padding(17)
            }
            HStack {
                Button { store.newAgentDirectory = ""; store.showNewAgent = true } label: { Label("New agent", systemImage: "plus") }.buttonStyle(.plain)
                Spacer()
                Button { store.showSettings = true } label: { HStack { Text("Settings"); Image(systemName: "chevron.right").font(.system(size: 10)) } }.buttonStyle(.plain)
            }.font(.system(size: 12)).foregroundStyle(.gray).padding(17).background(.white.opacity(0.03))
        }.onAppear { store.refreshDiscoveryIfNeeded(force: true) }
    }
    @ViewBuilder private func directorySections(_ sections: [AgentDirectorySection]) -> some View {
        ForEach(sections) { section in
            HStack {
                Text(section.worktreeName.map { "↳ \($0) · worktree" } ?? "Main checkout").font(.system(size: 11)).foregroundStyle(.gray).help(section.id)
                Spacer()
                Button { store.trackWorktree(section.id, enabled: false) } label: { Image(systemName: "minus.circle").font(.system(size: 12)) }
                    .buttonStyle(.plain).help("Remove this worktree from tracking").accessibilityLabel("Remove worktree \(section.id)")
            }.padding(.leading, section.worktreeName == nil ? 0 : 14)
            ForEach(section.agents) { agent in
                HStack(spacing: 10) {
                    Button {
                        store.search = ""
                        store.setInboxScope(agent.state == .working ? .running : store.reviewAgents.contains(where: { $0.id == agent.id }) ? .review : .all)
                        store.selection = agent.id; store.showingNotice = false
                        store.onRevealInbox?()
                    } label: {
                        HStack(spacing: 11) {
                            StatusDot(state: agent.state)
                            ProviderLogo(provider: agent.provider, size: 20)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(agent.displayTitle).font(.system(size: 14, weight: .medium)).lineLimit(1)
                                if let request = ConversationContext(agent).latestRequest {
                                    Text("You: \(ConversationContext.excerpt(request.text, limit: 160))").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            Text(agent.state.label).font(.system(size: 10)).foregroundStyle(.secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(agent.name)
                    Button { store.selection = agent.id; store.tab = "Talk" } label: { Image(systemName: "bubble.left").frame(width: 22, height: 24) }.buttonStyle(.plain).disabled(store.voiceRecording).accessibilityLabel("Talk to \(agent.name)")
                    Button { store.trackConversation(agent.id, enabled: false) } label: { Image(systemName: "xmark").font(.system(size: 10)).frame(width: 20, height: 24) }.buttonStyle(.plain).help("Remove conversation from tracking").accessibilityLabel("Remove \(agent.name) from tracking")
                }.padding(.vertical, 3).padding(.leading, section.worktreeName == nil ? 0 : 14)
            }
        }
    }
    private func create(_ provider: String, path: String) { store.newAgentProvider = provider; store.newAgentDirectory = path; store.showNewAgent = true }
}
struct NewAgentView: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var provider = "Codex"
    @State private var directory = ""
    @State private var prompt = ""
    private var forkSource: Agent? { store.snapshot.agents.first { $0.id == store.forkSourceID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(forkSource == nil ? "Start an agent" : "Fork in Open One").font(.system(size: 22, weight: .semibold))
            Text(forkSource == nil ? "A local session, using your existing CLI sign-in." : "Create a separate conversation from this session's history, in the same project.").font(.system(size: 12)).foregroundStyle(.secondary)
            Picker("Agent", selection: $provider) { Text("Codex").tag("Codex"); Text("Claude Code").tag("Claude") }.pickerStyle(.segmented).disabled(forkSource != nil)
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("PROJECT").font(.system(size: 9, weight: .semibold)).foregroundStyle(.gray); Text(directory.isEmpty ? "Choose a project folder" : directory).font(.system(size: 12)).lineLimit(2) }
                Spacer()
                Button("Choose…") { let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false; if p.runModal() == .OK { directory = p.url?.path ?? "" } }.disabled(forkSource != nil)
            }
            TextField("What should the agent do?", text: $prompt, axis: .vertical).lineLimit(4...8).textFieldStyle(.plain).padding(12).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            Text("Choose a project you trust. Its CLI settings and permissions apply. Command requests appear here for you to approve once or deny.").font(.system(size: 11)).foregroundStyle(.secondary)
            if forkSource == nil, let image = store.attachment { AttachmentPreview(image: image) { store.attachment = nil } }
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button(forkSource == nil ? "Start agent" : "Fork and send") { store.createAgent(provider: provider, directory: directory, prompt: prompt, forkFrom: forkSource, image: forkSource == nil ? store.attachment : nil); dismiss() }.buttonStyle(.borderedProminent).disabled(store.pending != nil || directory.isEmpty || (prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (forkSource != nil || store.attachment == nil))) }
        }.padding(28).frame(width: 440).preferredColorScheme(.dark)
            .onAppear { provider = store.newAgentProvider; directory = store.newAgentDirectory; prompt = store.forkPrompt ?? store.draft; if let source = forkSource { provider = source.provider; directory = source.directory } }
    }
}

struct SettingsView: View {
    @AppStorage("doubleControlEnabled") private var doubleControlEnabled = true
    @ObservedObject var store: Store
    var close: (() -> Void)? = nil
    @Environment(\.dismiss) var dismiss
    @State private var showTracking = false
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 19) {
            HStack(spacing: 10) {
                BrandLogo().accessibilityHidden(true)
                Text("Settings").font(.system(size: 22, weight: .semibold))
                Spacer()
                Button("Done") { if let close { close() } else { dismiss() } }.keyboardShortcut(.cancelAction)
            }
            Label("Local by default", systemImage: "desktopcomputer").font(.system(size: 13, weight: .semibold))
            Text("Open One stores its Inbox on this Mac. Agent requests go through the CLI you choose. Voice transcription uses Apple's speech service after you allow it.").font(.system(size: 12)).foregroundStyle(.secondary)
            Divider()
            Button("Connect agents — guided setup…") { store.onOnboardingRequested?() }
            ConnectionSettings(store: store)
            Button("Tracked worktrees and conversations…") { showTracking = true }
            Divider()
            DisclosureGroup("Archived conversations (\(store.archivedAgents.count))") {
                if store.archivedAgents.isEmpty { Text("Nothing archived yet.").font(.system(size: 11)).foregroundStyle(.secondary) }
                ForEach(store.archivedAgents) { agent in
                    HStack {
                        VStack(alignment: .leading) { Text(agent.name); Text(agent.title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer()
                        Button("Restore") { store.restoreAgent(agent.id) }
                    }.font(.system(size: 12)).padding(.vertical, 4)
                }
            }
            Divider()
            Toggle("Discover local Codex and Claude sessions", isOn: Binding(get: { store.discoveryEnabled }, set: { store.setDiscoveryEnabled($0) })).font(.system(size: 13, weight: .semibold))
            Text("Observes up to 40 sessions updated in the past 24 hours, refreshed every 15 seconds. System prompts and tool output are excluded. Send continues a saved Claude or Codex conversation; Fork creates a separate one. Close the conversation in its original app before continuing here.").font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                Button(store.discovering ? "Scanning…" : "Refresh now") { store.refreshDiscoveryIfNeeded(force: true) }.disabled(!store.discoveryEnabled || store.discovering || store.demo)
                if let message = store.discoveryNotice { Text(message).font(.system(size: 11)).foregroundStyle(.orange) }
            }
            Divider()
            Text("AI routing").font(.system(size: 14, weight: .semibold))
            Text("Talk shows an on-device recipient recommendation as you type. When you choose Ask AI to recommend, Claude Code receives your draft, candidate names, project/worktree names, task titles, and the latest request (up to 800 characters), latest message (up to 600), and six recent user/assistant messages (up to 400 each), with speaker, time, state and selected conversation. It has no tools. Review the suggested recipient before sending.").font(.system(size: 12)).foregroundStyle(.secondary)
            Text("Screen capture").font(.system(size: 14, weight: .semibold))
            Text("Drag a region, or press Space to select a window. Captures stay on this Mac until you send them to a managed Codex or Claude session. Allow Open One in Screen Recording settings; if macOS asks, quit and reopen the app, then try again.").font(.system(size: 12)).foregroundStyle(.secondary)
            Button("Open Screen Recording settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }
            Divider()
            Text("Connect an existing agent").font(.system(size: 14, weight: .semibold))
            Text("Use the bundled one CLI to publish status, ask a question and receive the answer. No terminal sessions are modified automatically.").font(.system(size: 12)).foregroundStyle(.secondary)
            Text("one ask --agent my-agent --question 'Which layout?' --option 'Three tiers' --option 'One plan'")
                .font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            Text("LOCAL DATA").font(.system(size: 9, weight: .semibold)).foregroundStyle(.gray)
            Text(store.root.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            Divider()
            Text("Shortcuts").font(.system(size: 14, weight: .semibold))
            Toggle("Double-tap Control to open Talk", isOn: $doubleControlEnabled)
                .font(.system(size: 12))
            Text("On by default. Tap Control twice to open Talk. Option is not used. Open One is also available from its toolbar or menu bar.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Text("When Open One is focused: ⌘1 Inbox · ⌘2 Talk · ⌘N New agent\nJ / K Move · 1–9 Answer · E Review / archive · Escape Undo / close")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
            Text("Independent recreation. Not affiliated with One or its creator. Remote access uses your own encrypted tunnel; no One account or hosted relay is used.").font(.system(size: 10)).foregroundStyle(.gray)
        }.padding(28) }.frame(width: 520, height: 620).preferredColorScheme(.dark)
            .sheet(isPresented: $showTracking) { TrackingView(store: store) }
    }
}

extension Notification.Name {
    static let startVoice = Notification.Name("OpenOne.startVoice")
    static let stopVoice = Notification.Name("OpenOne.stopVoice")
    static let focusComposer = Notification.Name("OpenOne.focusComposer")
}
