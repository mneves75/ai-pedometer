import Foundation
import os

/// Performance signpost wrapper for Instruments integration.
/// Use `Signposts.category.begin/end()` for interval measurements.
///
/// Signpost intervals appear in Instruments > os_signpost and provide
/// precise timing data for performance profiling.
struct SignpostLogger: Sendable {
    private let signposter: OSSignposter
    let categoryName: String

    init(subsystem: String, category: String) {
        self.signposter = OSSignposter(subsystem: subsystem, category: category)
        self.categoryName = category
    }

    /// Begin an interval. Returns a state to pass to `end()`.
    func begin(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    /// End an interval with the state from `begin()`.
    func end(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }

    /// Measure an async operation automatically with typed throws support.
    @discardableResult
    func measure<T: Sendable, E: Error>(
        _ name: StaticString,
        operation: @Sendable () async throws(E) -> T
    ) async throws(E) -> T {
        let state = begin(name)
        defer { end(name, state) }
        return try await operation()
    }

    /// Measure a synchronous operation automatically with typed throws support.
    @discardableResult
    func measureSync<T, E: Error>(
        _ name: StaticString,
        operation: () throws(E) -> T
    ) throws(E) -> T {
        let state = begin(name)
        defer { end(name, state) }
        return try operation()
    }

    /// Emit a single signpost event (not an interval).
    func event(_ name: StaticString) {
        signposter.emitEvent(name)
    }
}

/// Predefined signpost loggers organized by category.
/// Usage: `Signposts.ai.measure("DailyInsight") { await generateInsight() }`
enum Signposts {
    static let ai = SignpostLogger(
        subsystem: AppConstants.bundleIdentifier,
        category: "ai"
    )
    static let health = SignpostLogger(
        subsystem: AppConstants.bundleIdentifier,
        category: "health"
    )
    static let tracking = SignpostLogger(
        subsystem: AppConstants.bundleIdentifier,
        category: "tracking"
    )
    static let startup = SignpostLogger(
        subsystem: AppConstants.bundleIdentifier,
        category: "startup"
    )
    static let sync = SignpostLogger(
        subsystem: AppConstants.bundleIdentifier,
        category: "sync"
    )
}
