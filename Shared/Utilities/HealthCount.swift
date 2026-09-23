import Foundation

/// Integer view of a HealthKit quantity (steps, pushes, floors, heart rate).
///
/// HealthKit sums include samples from any app with write access, so a value can be non-finite,
/// negative or beyond `Int`'s range, where `Int(_: Double)` traps. The cap keeps any realistic sum of
/// days far from overflow.
enum HealthCount {
    static let maximum = Double(Int32.max)

    static func clamped(_ value: Double) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        return Int(min(value, maximum))
    }
}
