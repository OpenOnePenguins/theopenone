import Foundation

public enum CardNavigation {
    /// Keep the current card in a small, bounded rail even with many discovered sessions.
    public static func visibleRange(count: Int, selection: Int, limit: Int = 7) -> Range<Int> {
        guard count > 0, limit > 0 else { return 0..<0 }
        let width = min(count, limit)
        let selected = max(0, min(count - 1, selection))
        let start = max(0, min(count - width, selected - width / 2))
        return start..<(start + width)
    }
}
