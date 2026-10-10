import CoreGraphics

/// Once a press becomes a drag, returning to the starting point must not trigger a click.
public struct ToolbarGesture {
    public private(set) var dragging = false
    private let start: CGPoint
    public init(start: CGPoint) { self.start = start }
    @discardableResult public mutating func update(_ point: CGPoint) -> Bool {
        if hypot(point.x - start.x, point.y - start.y) >= 4 { dragging = true }
        return dragging
    }
    public func shouldClick(releasedInside: Bool) -> Bool { !dragging && releasedInside }
}
