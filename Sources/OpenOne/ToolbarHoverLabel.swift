import AppKit
import SwiftUI
import QuartzCore

/// A separate, noninteractive surface lets labels extend beyond the narrow dock
/// without enlarging its mouse target or rescaling the icon underneath.
final class ToolbarHoverLabelPresenter {
    static let shared = ToolbarHoverLabelPresenter()
    private weak var owner: NSView?
    private var panel: NSPanel?
    private var generation = 0

    func show(_ text: String, from view: NSView, onRight: Bool) {
        guard let window = view.window, window.isVisible else { return }
        generation += 1
        owner = view
        let font = NSFont.systemFont(ofSize: 16, weight: .medium)
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width) + 36
        let target = window.convertToScreen(view.convert(view.bounds, to: nil))
        var frame = NSRect(x: onRight ? target.maxX + 3 - width : target.minX - 3, y: target.midY - 19.5, width: width, height: 39)
        if let screen = window.screen {
            frame.origin.x = min(max(frame.minX, screen.visibleFrame.minX + 2), screen.visibleFrame.maxX - width - 2)
        }
        let surface: NSPanel
        if let panel { surface = panel }
        else {
            surface = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            surface.isOpaque = false; surface.backgroundColor = .clear; surface.hasShadow = true
            surface.ignoresMouseEvents = true; surface.hidesOnDeactivate = false
            surface.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            surface.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = surface
        }
        surface.contentView = NSHostingView(rootView:
            Text(text).font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                .fixedSize().frame(width: width, height: 39)
                .background(.black.opacity(0.94), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                .preferredColorScheme(.dark)
        )
        // Fade only: text and glyphs remain at their native pixel resolution.
        frame.origin.x = frame.origin.x.rounded(); frame.origin.y = frame.origin.y.rounded()
        surface.setFrame(frame, display: true)
        surface.alphaValue = 0
        surface.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.05 : 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            surface.animator().alphaValue = 1
        }
    }
    func hide(from view: NSView) {
        guard owner === view, let panel else { return }
        generation += 1
        let current = generation
        owner = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.07
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak panel] in
            DispatchQueue.main.async {
                guard self?.generation == current else { return }
                panel?.orderOut(nil)
            }
        })
    }
}
