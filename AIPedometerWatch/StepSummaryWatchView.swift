#if os(watchOS)
import SwiftUI

struct StepSummaryWatchView: View {
    let steps: Int
    let goal: Int
    let streak: Int
    let distanceText: String

    private var progress: Double {
        goal > 0 ? min(Double(steps) / Double(goal), 1.0) : 0
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 10)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(colors: [.mint, .cyan], center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(steps)")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                        .monospacedDigit()
                    Text(String(localized: "steps", comment: "Watch steps unit"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 110)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label(String(localized: "Distance", comment: "Watch distance label"), systemImage: "figure.walk")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(distanceText)
                        .font(.caption.weight(.semibold))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Label(String(localized: "Streak", comment: "Watch streak label"), systemImage: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(
                        Localization.format(
                            "%lld days",
                            comment: "Watch streak value in days",
                            Int64(streak)
                        )
                    )
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .padding()
    }
}

#Preview {
    StepSummaryWatchView(steps: 6540, goal: 10_000, streak: 12, distanceText: "4.2 km")
}
#endif
