import Foundation

enum ProgressClamp {
    static func unitInterval(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    static func percent(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return max(Int((max(value, 0) * 100).rounded(.down)), 0)
    }
}
