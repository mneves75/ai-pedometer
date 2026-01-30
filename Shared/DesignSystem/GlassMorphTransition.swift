import SwiftUI

struct GlassMorphTransitionModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffectID(id, in: namespace)
        } else {
            content
                .matchedGeometryEffect(id: id, in: namespace)
        }
    }
}

extension View {
    func glassMorphTransition(id: String, namespace: Namespace.ID) -> some View {
        modifier(GlassMorphTransitionModifier(id: id, namespace: namespace))
    }
}
