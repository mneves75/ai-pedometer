import SwiftUI
import SwiftFastMarkdown

/// Markdown configuration for AI chat rendering (iOS-only).
///
/// Goals:
/// - Fast incremental rendering for streaming content
/// - Safe defaults (no raw HTML blocks/spans)
/// - Visual consistency with DesignTokens
enum AIChatMarkdown {
    /// GFM-ish subset + hard breaks + HTML disabled (avoid HTML injection / layout surprises).
    static let parseOptions: ParseOptions = [
        .gfmSubset,
        .hardSoftBreaks,
        .noHTMLBlocks,
        .noHTMLSpans
    ]

    static let style: MarkdownStyle = MarkdownStyle(
        baseFont: DesignTokens.Typography.subheadline,
        codeFont: DesignTokens.Typography.subheadlineMonospaced,
        headingFonts: [
            DesignTokens.Typography.title2.bold(),
            DesignTokens.Typography.title3.bold(),
            DesignTokens.Typography.headline.weight(.semibold),
            DesignTokens.Typography.subheadline.weight(.semibold),
            DesignTokens.Typography.subheadline.weight(.medium),
            DesignTokens.Typography.subheadline.weight(.medium)
        ],
        linkColor: DesignTokens.Colors.accent,
        textColor: DesignTokens.Colors.textPrimary,
        codeTextColor: DesignTokens.Colors.textPrimary,
        codeBackgroundColor: DesignTokens.Colors.surfaceQuaternary,
        quoteStripeColor: DesignTokens.Colors.textSecondary,
        blockSpacing: 1,
        listIndent: 2
    )

    static func parseDocument(from markdown: String) throws -> MarkdownDocument {
        try MarkdownParser().parse(markdown, options: parseOptions)
    }

    static func makeIncrementalParser(minBufferSize: Int = 32) -> IncrementalMarkdownParser {
        IncrementalMarkdownParser(
            configuration: IncrementalMarkdownParser.Configuration(
                options: parseOptions,
                minBufferSize: minBufferSize
            )
        )
    }

    static func renderAttributedString(from document: MarkdownDocument) -> AttributedString {
        AttributedStringRenderer().render(document, style: style)
    }
}

