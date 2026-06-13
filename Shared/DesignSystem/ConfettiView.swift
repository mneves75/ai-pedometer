import SwiftUI

/// A lightweight, self-contained confetti burst rendered with `Canvas` driven by
/// `TimelineView`. It draws a fixed set of particles that fall and fade over a
/// short lifetime, so there is no retained simulation state and no per-frame
/// allocation.
///
/// Honors Reduce Motion: when the system setting is on (or under UI testing) the
/// view renders nothing, so callers can place it unconditionally.
struct ConfettiView: View {
    /// Number of particles. Kept small; the effect reads as celebratory without
    /// becoming a particle system.
    var particleCount: Int = 60

    /// Total animation lifetime in seconds.
    var duration: Double = 2.2

    /// Palette the particles are drawn from.
    var colors: [Color] = [
        DesignTokens.Colors.mint,
        DesignTokens.Colors.cyan,
        DesignTokens.Colors.yellow,
        DesignTokens.Colors.accent,
        DesignTokens.Colors.orange
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var isFinished = false

    private var isEnabled: Bool {
        !reduceMotion && !LaunchConfiguration.isUITesting()
    }

    var body: some View {
        Group {
            if isEnabled && !isFinished {
                // `paused` is bound to `isFinished` so the 60 FPS timeline stops
                // ticking the moment the burst lifetime ends, even if the host
                // overlay (e.g. a celebration sheet) stays mounted afterward.
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: isFinished)) { context in
                    Canvas { canvas, size in
                        guard let start else { return }
                        let elapsed = context.date.timeIntervalSince(start)
                        guard elapsed <= duration else { return }
                        draw(in: &canvas, size: size, elapsed: elapsed)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .task {
                    start = .now
                    try? await Task.sleep(for: .seconds(duration))
                    isFinished = true
                }
            }
        }
    }

    private func draw(in canvas: inout GraphicsContext, size: CGSize, elapsed: Double) {
        let progress = elapsed / duration
        let fade = 1.0 - progress

        for index in 0..<particleCount {
            let particle = Particle(index: index, count: particleCount)
            let x = particle.originX * size.width + particle.drift * elapsed * size.width
            let fallDistance = particle.speed * elapsed * elapsed * size.height
            let y = particle.originY * size.height + fallDistance
            guard y < size.height + DesignTokens.Spacing.lg else { continue }

            let rect = CGRect(
                x: x,
                y: y,
                width: particle.size,
                height: particle.size * 1.6
            )
            let color = colors[index % colors.count].opacity(fade)
            let rotation = Angle.radians(particle.spin * elapsed)

            canvas.drawLayer { layer in
                layer.translateBy(x: rect.midX, y: rect.midY)
                layer.rotate(by: rotation)
                layer.translateBy(x: -rect.midX, y: -rect.midY)
                layer.fill(
                    Path(roundedRect: rect, cornerRadius: DesignTokens.CornerRadius.xs * 0.5),
                    with: .color(color)
                )
            }
        }
    }
}

/// Deterministic per-particle parameters derived from the index, so the burst is
/// stable across frames without storing any state. Hash-based jitter avoids
/// `Math.random()` (unavailable / non-deterministic) while still looking organic.
private struct Particle {
    let originX: Double
    let originY: Double
    let drift: Double
    let speed: Double
    let spin: Double
    let size: CGFloat

    init(index: Int, count: Int) {
        let unit = Double(index) / Double(max(count, 1))
        // Cheap, deterministic pseudo-jitter from the index.
        let jitterA = Particle.jitter(index, salt: 17)
        let jitterB = Particle.jitter(index, salt: 53)
        let jitterC = Particle.jitter(index, salt: 91)

        originX = unit
        originY = -0.1 - jitterA * 0.2
        drift = (jitterB - 0.5) * 0.18
        speed = 0.55 + jitterC * 0.6
        spin = (jitterA - 0.5) * 12
        size = DesignTokens.Spacing.xs + CGFloat(jitterB) * DesignTokens.Spacing.xs
    }

    /// Returns a value in 0..<1 from an integer and salt.
    ///
    /// Uses `UInt32` wrapping arithmetic so the multiplicative-hash constant is
    /// well-defined on 32-bit-`Int` platforms (watchOS/arm64_32), where a plain
    /// `Int` literal of `2_654_435_761` would overflow.
    static func jitter(_ value: Int, salt: Int) -> Double {
        let v = UInt32(truncatingIfNeeded: value)
        let s = UInt32(truncatingIfNeeded: salt)
        let mixed = (v &* 2_654_435_761 &+ s &* 40_503) & 0xFFFF
        return Double(mixed) / Double(0xFFFF)
    }
}
