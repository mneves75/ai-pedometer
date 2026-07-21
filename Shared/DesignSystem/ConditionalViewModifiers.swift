import SwiftUI

extension View {
    @ViewBuilder
    func applyIfNotUITesting<Content: View>(
        _ transform: (Self) -> Content
    ) -> some View {
        if LaunchConfiguration.isUITesting() {
            self
        } else {
            transform(self)
        }
    }

    func applyIfMotionEnabled<Content: View>(
        _ transform: @escaping (Self) -> Content
    ) -> some View {
        MotionEnabledTransform(base: self, transform: transform)
    }

    func motionAwareAnimation<Value: Equatable>(
        _ animation: Animation?,
        value: Value
    ) -> some View {
        modifier(MotionAwareAnimationModifier(animation: animation, value: value))
    }

    /// Adds a stable accessibility marker only when UI testing.
    ///
    /// SwiftUI containers (e.g. `VStack`, `ScrollView`) don't always surface `accessibilityIdentifier`
    /// reliably in the accessibility tree. This creates a tiny element that UI tests can assert on.
    @ViewBuilder
    func uiTestMarker(_ identifier: String) -> some View {
        if LaunchConfiguration.isUITesting() {
            overlay(alignment: .topLeading) {
                UITestMarkerView(identifier: identifier)
                    .allowsHitTesting(false)
            }
        } else {
            self
        }
    }

    /// Adds a marker for a state that is meaningful to UI automation without
    /// requiring the corresponding visual content to be onscreen.
    @ViewBuilder
    func uiTestMarker(_ identifier: String, when condition: Bool) -> some View {
        if condition {
            uiTestMarker(identifier)
        } else {
            self
        }
    }
}

private struct MotionEnabledTransform<Base: View, Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let base: Base
    let transform: (Base) -> Content

    var body: some View {
        if LaunchConfiguration.isUITesting() || reduceMotion {
            base
        } else {
            transform(base)
        }
    }
}

private struct MotionAwareAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation?
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

private struct UITestMarkerView: View {
    let identifier: String

    var body: some View {
        // A transparent foreground keeps the element in the accessibility tree
        // without leaving faint automation text in captured UI.
        Text(identifier)
            .font(.system(size: 1))
            .foregroundStyle(.clear)
            .frame(width: 1, height: 1)
            .clipped()
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(identifier)
    }
}
