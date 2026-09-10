import Foundation
import os

/// Performance signpost wrapper for Instruments integration.
/// Use `Signposts.category.begin/end()` for interval measurements.
///
/// Signpost intervals appear in Instruments > os_signpost and provide
/// precise timing data for performance profiling.
struct SignpostLogger: Sendable {
    private let signposter: OSSignposter

    init(subsystem: String, category: String) {
        self.signposter = OSSignposter(subsystem: subsystem, category: category)
    }

    /// Begin an interval. Returns a state to pass to `end()`.
    func begin(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    /// End an interval with the state from `begin()`.
    func end(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }

    /// Emit a single signpost event (not an interval).
    func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}

/// Predefined signpost loggers organized by category.
/// Usage: `let state = Signposts.ai.begin("DailyInsight")` … `Signposts.ai.end("DailyInsight", state)`
enum Signposts {
    static let ai = SignpostLogger(
        subsystem: AppConstants.bundleIdentifier,
        category: "ai"
    )
    static let sync = SignpostLogger(
        subsystem: AppConstants.bundleIdentifier,
        category: "sync"
    )
}
