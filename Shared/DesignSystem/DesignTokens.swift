import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum DesignTokens {
    enum FontSize {
        static let xxl: CGFloat = 80
        static let xl: CGFloat = 64
        static let lg: CGFloat = 60
        static let md: CGFloat = 48
        static let sm: CGFloat = 44
        static let xs: CGFloat = 40
        static let widgetLg: CGFloat = 36
        static let widgetMd: CGFloat = 32
        static let widgetSm: CGFloat = 30
    }

    enum Spacing {
        static let none: CGFloat = 0
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let xsPlus: CGFloat = 6
        static let sm: CGFloat = 8
        static let smPlus: CGFloat = 12
        static let md: CGFloat = 16
        static let mdPlus: CGFloat = 20
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

    enum Opacity {
        // Keep "magic numbers" centralized as tokens.
        static let textTertiary: Double = 0.8
        static let textQuaternary: Double = 0.6
        static let surfaceElevated: Double = 0.06
        static let surfaceQuaternary: Double = 0.04
        static let borderMuted: Double = 0.12
    }

    enum Colors {
        static let accent = Color.accentColor
        static let accentMuted = Color.accentColor.opacity(0.2)
        static let accentSoft = Color.accentColor.opacity(0.12)

        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static var textTertiary: Color {
#if canImport(UIKit) && !os(watchOS)
            Color(uiColor: .tertiaryLabel)
#else
            // watchOS doesn't expose UIKit semantic label colors (tertiary/quaternary). Use SwiftUI semantics.
            Color.secondary.opacity(DesignTokens.Opacity.textTertiary)
#endif
        }

        static var textQuaternary: Color {
#if canImport(UIKit) && !os(watchOS)
            Color(uiColor: .quaternaryLabel)
#else
            Color.secondary.opacity(DesignTokens.Opacity.textQuaternary)
#endif
        }

        static var surface: Color {
#if canImport(UIKit) && !os(watchOS)
            Color(uiColor: .systemBackground)
#else
            // watchOS is effectively always "dark first"; this maps best to the platform's typical background.
            Color.black
#endif
        }

        static var surfaceGrouped: Color {
#if canImport(UIKit) && !os(watchOS)
            Color(uiColor: .systemGroupedBackground)
#else
            Color.black
#endif
        }

        static var surfaceElevated: Color {
#if canImport(UIKit) && !os(watchOS)
            Color(uiColor: .secondarySystemGroupedBackground)
#else
            Color.white.opacity(DesignTokens.Opacity.surfaceElevated)
#endif
        }

        static var surfaceQuaternary: Color {
#if canImport(UIKit) && !os(watchOS)
            Color(uiColor: .quaternarySystemFill)
#else
            Color.white.opacity(DesignTokens.Opacity.surfaceQuaternary)
#endif
        }

        static var borderMuted: Color {
#if canImport(UIKit) && !os(watchOS)
            Color(uiColor: .systemGray4)
#else
            Color.white.opacity(DesignTokens.Opacity.borderMuted)
#endif
        }

        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red

        static let mint = Color.mint
        static let cyan = Color.cyan
        static let yellow = Color.yellow
        static let blue = Color.blue
        static let purple = Color.purple
        static let green = success
        static let orange = warning
        static let red = error

        static let inverseText = Color.white
        static let inverseStroke = Color.white.opacity(0.15)
        static let overlayDark = Color.black.opacity(0.4)
        static let overlayDim = Color.black.opacity(0.3)
    }

    enum Typography {
        static let largeTitle = Font.largeTitle
        static let title = Font.title
        static let title2 = Font.title2
        static let title3 = Font.title3
        static let headline = Font.headline
        static let callout = Font.callout
        static let body = Font.body
        static let subheadline = Font.subheadline
        static let caption = Font.caption
        static let caption2 = Font.caption2
        static let footnote = Font.footnote
        static let title2Rounded = Font.system(.title2, design: .rounded)
        static let bodyMonospaced = Font.system(.body, design: .monospaced)
        static let subheadlineMonospaced = Font.system(.subheadline, design: .monospaced)
    }

    enum Sizing {
        static let progressRing: CGFloat = 230
        static let progressRingLineWidth: CGFloat = 16
    }

    enum TouchTarget {
        static let minimum: CGFloat = 44
    }
}
