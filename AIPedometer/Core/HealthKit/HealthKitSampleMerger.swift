import Foundation

struct HealthKitSampleValue: Sendable {
    let start: Date
    let end: Date
    let value: Double
    let sourceBundleIdentifier: String?
    let productType: String?
    let deviceModel: String?
    let deviceName: String?
}

struct HealthKitSampleMerger {
    struct MergeResult: Sendable {
        let total: Double
        let prioritiesPresent: Set<HealthKitSourcePolicy.Priority>
        let overlapSeconds: TimeInterval
        let segmentCount: Int

        var mergedSources: Bool {
            prioritiesPresent.count > 1
        }
    }

    struct DailyMergeResult: Sendable {
        let totals: [Date: Double]
        let daysWithMultipleSources: Int
        let daysWithOverlap: Int
        let totalDays: Int
        let segmentCount: Int
    }

    private struct Segment: Sendable {
        let start: Date
        let end: Date
        let valuePerSecond: Double
        let priority: HealthKitSourcePolicy.Priority

        var interval: DateInterval {
            DateInterval(start: start, end: end)
        }

        var duration: TimeInterval {
            max(0, end.timeIntervalSince(start))
        }
    }

    static func mergeTotal(samples: [HealthKitSampleValue]) -> MergeResult {
        let segments = samples.compactMap { makeSegment(sample: $0) }
        return mergeSegments(segments)
    }

    static func mergeDailyTotals(
        samples: [HealthKitSampleValue],
        calendar: Calendar,
        from startDate: Date,
        to endDate: Date
    ) -> DailyMergeResult {
        guard startDate <= endDate else {
            return DailyMergeResult(
                totals: [:],
                daysWithMultipleSources: 0,
                daysWithOverlap: 0,
                totalDays: 0,
                segmentCount: 0
            )
        }

        let segmentsByDay = splitSegmentsByDay(samples: samples, calendar: calendar)
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)

        var totals: [Date: Double] = [:]
        var daysWithMultipleSources = 0
        var daysWithOverlap = 0
        var segmentCount = 0

        var current = startDay
        while current <= endDay {
            let segments = segmentsByDay[current] ?? []
            let result = mergeSegments(segments)
            totals[current] = result.total
            segmentCount += result.segmentCount
            if result.mergedSources {
                daysWithMultipleSources += 1
            }
            if result.overlapSeconds > 0 {
                daysWithOverlap += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        let totalDays = max(0, calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1
        return DailyMergeResult(
            totals: totals,
            daysWithMultipleSources: daysWithMultipleSources,
            daysWithOverlap: daysWithOverlap,
            totalDays: totalDays,
            segmentCount: segmentCount
        )
    }

    private static func makeSegment(sample: HealthKitSampleValue) -> Segment? {
        let duration = sample.end.timeIntervalSince(sample.start)
        guard duration > 0 else { return nil }
        // Assume the quantity is uniformly distributed across the sample interval.
        let valuePerSecond = sample.value / duration
        let priority = HealthKitSourcePolicy.priority(for: sample)
        return Segment(start: sample.start, end: sample.end, valuePerSecond: valuePerSecond, priority: priority)
    }

    private static func splitSegmentsByDay(
        samples: [HealthKitSampleValue],
        calendar: Calendar
    ) -> [Date: [Segment]] {
        var result: [Date: [Segment]] = [:]

        for sample in samples {
            let totalDuration = sample.end.timeIntervalSince(sample.start)
            guard totalDuration > 0 else { continue }
            let valuePerSecond = sample.value / totalDuration
            let priority = HealthKitSourcePolicy.priority(for: sample)

            var currentStart = sample.start
            while currentStart < sample.end {
                let dayStart = calendar.startOfDay(for: currentStart)
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
                let segmentEnd = min(sample.end, nextDay)
                let segment = Segment(
                    start: currentStart,
                    end: segmentEnd,
                    valuePerSecond: valuePerSecond,
                    priority: priority
                )
                result[dayStart, default: []].append(segment)
                currentStart = segmentEnd
            }
        }

        return result
    }

    private static func mergeSegments(_ segments: [Segment]) -> MergeResult {
        guard !segments.isEmpty else {
            return MergeResult(total: 0, prioritiesPresent: [], overlapSeconds: 0, segmentCount: 0)
        }

        let grouped = Dictionary(grouping: segments, by: \.priority)
        let prioritiesPresent = Set(grouped.keys)

        var total = 0.0
        var covered: [DateInterval] = []
        var overlapSeconds: TimeInterval = 0

        let priorities = HealthKitSourcePolicy.Priority.allCases.sorted(by: >)
        for priority in priorities {
            guard let group = grouped[priority] else { continue }
            for segment in group {
                let duration = segment.duration
                guard duration > 0 else { continue }
                // Keep higher-priority data and only include uncovered portions of lower-priority samples.
                let overlap = overlapDuration(of: segment.interval, covered: covered)
                let uncovered = max(0, duration - overlap)
                overlapSeconds += overlap
                if uncovered > 0 {
                    total += segment.valuePerSecond * uncovered
                }
            }
            covered = mergeIntervals(covered + group.map(\.interval))
        }

        return MergeResult(
            total: total,
            prioritiesPresent: prioritiesPresent,
            overlapSeconds: overlapSeconds,
            segmentCount: segments.count
        )
    }

    private static func mergeIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []

        for interval in sorted {
            guard interval.duration > 0 else { continue }
            if let last = merged.last, interval.start <= last.end {
                let newEnd = max(last.end, interval.end)
                merged[merged.count - 1] = DateInterval(start: last.start, end: newEnd)
            } else {
                merged.append(interval)
            }
        }

        return merged
    }

    private static func overlapDuration(of interval: DateInterval, covered: [DateInterval]) -> TimeInterval {
        guard interval.duration > 0 else { return 0 }
        var overlap: TimeInterval = 0
        for coveredInterval in covered {
            if coveredInterval.start >= interval.end {
                break
            }
            if coveredInterval.end <= interval.start {
                continue
            }
            let start = max(interval.start, coveredInterval.start)
            let end = min(interval.end, coveredInterval.end)
            if end > start {
                overlap += end.timeIntervalSince(start)
            }
        }
        return overlap
    }
}
