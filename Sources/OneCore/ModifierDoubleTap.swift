import Foundation

/// Two short, isolated presses; ordinary Control shortcuts must never open Talk.
public struct ModifierDoubleTap {
    private var pressedAt: TimeInterval?
    private var releasedAt: TimeInterval?
    private let interval: TimeInterval = 0.35
    public init() {}

    public mutating func cancel() { pressedAt = nil; releasedAt = nil }

    public mutating func update(pressed: Bool, otherModifiers: Bool, at now: TimeInterval) -> Bool {
        guard !otherModifiers else { cancel(); return false }
        if pressed {
            if pressedAt == nil { pressedAt = now }
            return false
        }
        guard let start = pressedAt else { return false }
        pressedAt = nil
        guard now >= start, now - start <= interval else { releasedAt = nil; return false }
        if let previous = releasedAt, start >= previous, now - previous <= interval {
            releasedAt = nil
            return true
        }
        releasedAt = now
        return false
    }
}
