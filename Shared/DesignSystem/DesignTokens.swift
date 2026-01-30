import SwiftUI

enum DesignTokens {
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
    }

    enum Animation {
        static let defaultDuration: Double = 0.25
        static let shortDuration: Double = 0.2
        static let longDuration: Double = 0.35

        static var snappy: SwiftUI.Animation {
            .snappy(duration: defaultDuration)
        }

        static var smooth: SwiftUI.Animation {
            .smooth(duration: defaultDuration)
        }

        static var springy: SwiftUI.Animation {
            .spring(response: 0.3, dampingFraction: 0.7)
        }

        static var bouncy: SwiftUI.Animation {
            .spring(response: 0.35, dampingFraction: 0.6)
        }
    }

    enum Shadow {
        static let subtle = (color: Color.black.opacity(0.08), radius: CGFloat(8), x: CGFloat(0), y: CGFloat(4))
        static let medium = (color: Color.black.opacity(0.12), radius: CGFloat(16), x: CGFloat(0), y: CGFloat(8))
        static let strong = (color: Color.black.opacity(0.18), radius: CGFloat(24), x: CGFloat(0), y: CGFloat(12))
    }

    enum TouchTarget {
        static let minimum: CGFloat = 44
    }
}
