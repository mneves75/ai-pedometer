import Foundation
import MetricKit
import os

/// Service for receiving and processing MetricKit performance payloads.
///
/// MetricKit delivers system-level performance metrics (launch time, memory, CPU, disk, etc.)
/// aggregated over 24-hour periods. This service logs payloads for observability and can
/// optionally forward them to an analytics backend.
///
/// Usage: Create once at app startup and retain for the app's lifetime.
@MainActor
final class MetricKitService: NSObject {
    static let shared = MetricKitService()

    private let logger = Logger(subsystem: "com.mneves.aipedometer", category: "metrics")

    override private init() {
        super.init()
        MXMetricManager.shared.add(self)
        logger.info("MetricKit service initialized")
    }

    deinit {
        MainActor.assumeIsolated {
            MXMetricManager.shared.remove(self)
        }
    }
}

extension MetricKitService: MXMetricManagerSubscriber {
    nonisolated private static func oneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            processMetricPayload(payload)
        }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            processDiagnosticPayload(payload)
        }
    }

    nonisolated private func processMetricPayload(_ payload: MXMetricPayload) {
        logger.info("""
            MetricKit daily payload received:
            - Period: \(payload.timeStampBegin.ISO8601Format()) to \(payload.timeStampEnd.ISO8601Format())
            """)

        // App launch metrics
        if let launchMetrics = payload.applicationLaunchMetrics {
            let firstDrawHistogram = launchMetrics.histogrammedTimeToFirstDraw
            let resumeHistogram = launchMetrics.histogrammedApplicationResumeTime

            logger.info("""
                Launch metrics:
                - Time to first draw buckets: \(firstDrawHistogram.totalBucketCount)
                - Resume time buckets: \(resumeHistogram.totalBucketCount)
                """)
        }

        // Memory metrics
        if let memoryMetrics = payload.memoryMetrics {
            let peakMB = memoryMetrics.peakMemoryUsage.converted(to: .megabytes).value
            let avgSuspendedMB = memoryMetrics.averageSuspendedMemory.averageMeasurement.converted(to: .megabytes).value

            logger.info("""
                Memory metrics:
                - Peak memory: \(Self.oneDecimal(peakMB)) MB
                - Avg suspended memory: \(Self.oneDecimal(avgSuspendedMB)) MB
                """)
        }

        // CPU metrics
        if let cpuMetrics = payload.cpuMetrics {
            let cpuTimeSec = cpuMetrics.cumulativeCPUTime.converted(to: .seconds).value
            let cpuInstructions = cpuMetrics.cumulativeCPUInstructions.value

            logger.info("""
                CPU metrics:
                - Cumulative CPU time: \(Self.oneDecimal(cpuTimeSec)) sec
                - CPU instructions: \(cpuInstructions)
                """)
        }

        // Disk I/O
        if let diskMetrics = payload.diskIOMetrics {
            let writesMB = diskMetrics.cumulativeLogicalWrites.converted(to: .megabytes).value

            logger.info("""
                Disk metrics:
                - Logical writes: \(Self.oneDecimal(writesMB)) MB
                """)
        }

        // Animation hitches (scrollHitchTimeRatio is ms per second)
        if let animationMetrics = payload.animationMetrics {
            let hitchRatioValue = animationMetrics.scrollHitchTimeRatio.value
            let hitchRatioStr = Self.oneDecimal(hitchRatioValue)

            logger.info("""
                Animation metrics:
                - Scroll hitch ratio: \(hitchRatioStr) ms/s
                """)
        }
    }

    nonisolated private func processDiagnosticPayload(_ payload: MXDiagnosticPayload) {
        logger.warning("""
            MetricKit diagnostic payload received:
            - Period: \(payload.timeStampBegin.ISO8601Format()) to \(payload.timeStampEnd.ISO8601Format())
            """)

        // Crash diagnostics
        if let crashDiagnostics = payload.crashDiagnostics {
            logger.error("Crash diagnostics count: \(crashDiagnostics.count)")

            for (index, crash) in crashDiagnostics.prefix(3).enumerated() {
                var crashInfo = "Crash \(index + 1):"
                if let exceptionType = crash.exceptionType {
                    crashInfo += " type=\(exceptionType)"
                }
                if let signal = crash.signal {
                    crashInfo += " signal=\(signal)"
                }
                if let terminationReason = crash.terminationReason {
                    crashInfo += " reason=\(terminationReason)"
                }
                logger.error("\(crashInfo)")
            }
        }

        // Hang diagnostics
        if let hangDiagnostics = payload.hangDiagnostics {
            logger.warning("Hang diagnostics count: \(hangDiagnostics.count)")

            for (index, hang) in hangDiagnostics.prefix(3).enumerated() {
                let durationSec = hang.hangDuration.converted(to: .seconds).value
                logger.warning("Hang \(index + 1): duration=\(Self.oneDecimal(durationSec))s")
            }
        }

        // CPU exception diagnostics
        if let cpuExceptions = payload.cpuExceptionDiagnostics {
            logger.warning("CPU exception diagnostics count: \(cpuExceptions.count)")
        }

        // Disk write exceptions
        if let diskExceptions = payload.diskWriteExceptionDiagnostics {
            logger.warning("Disk write exception diagnostics count: \(diskExceptions.count)")
        }
    }
}
