import Foundation
import CoreGraphics

public enum WindowPlacement {
    public static func docked(_ frame: CGRect, to visible: CGRect, right: Bool? = nil) -> CGRect {
        let placed = constrained(frame, to: visible, margin: 0)
        let onRight = right ?? (frame.midX >= visible.midX)
        return CGRect(x: onRight ? visible.maxX - placed.width : visible.minX,
                      y: placed.minY, width: placed.width, height: placed.height)
    }
    public static func constrained(_ frame: CGRect, to visible: CGRect, margin: CGFloat = 12) -> CGRect {
        let bounds = visible.insetBy(dx: margin, dy: margin)
        let width = min(frame.width, max(1, bounds.width))
        let height = min(frame.height, max(1, bounds.height))
        return CGRect(x: min(max(frame.minX, bounds.minX), bounds.maxX - width),
                      y: min(max(frame.minY, bounds.minY), bounds.maxY - height), width: width, height: height)
    }
}
