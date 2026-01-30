#if os(iOS)
import UIKit

@MainActor
public final class HapticService: Sendable {
    public static let shared = HapticService()

    private init() {}

    public func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    public func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    public func confirm() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    public func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    public func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    public func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    public func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

#elseif os(watchOS)
import WatchKit

@MainActor
public final class HapticService: Sendable {
    public static let shared = HapticService()

    private init() {}

    public func tap() {
        WKInterfaceDevice.current().play(.click)
    }

    public func selection() {
        WKInterfaceDevice.current().play(.click)
    }

    public func confirm() {
        WKInterfaceDevice.current().play(.click)
    }

    public func success() {
        WKInterfaceDevice.current().play(.success)
    }

    public func warning() {
        WKInterfaceDevice.current().play(.retry)
    }

    public func error() {
        WKInterfaceDevice.current().play(.failure)
    }
}

#else
// Stub for platforms without haptics (macOS, tvOS, visionOS)
@MainActor
public final class HapticService: Sendable {
    public static let shared = HapticService()

    private init() {}

    public func tap() {}
    public func selection() {}
    public func confirm() {}
    public func success() {}
    public func warning() {}
    public func error() {}
}
#endif
