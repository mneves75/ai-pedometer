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

    public func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
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

    public func error() {
        WKInterfaceDevice.current().play(.failure)
    }
}
#endif
