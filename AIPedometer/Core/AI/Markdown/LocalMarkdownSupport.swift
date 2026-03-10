import Foundation
import SwiftUI

struct ParseOptions: OptionSet {
    let rawValue: Int

    static let gfmSubset = ParseOptions(rawValue: 1 << 0)
    static let hardSoftBreaks = ParseOptions(rawValue: 1 << 1)
    static let noHTMLBlocks = ParseOptions(rawValue: 1 << 2)
    static let noHTMLSpans = ParseOptions(rawValue: 1 << 3)
}

struct MarkdownStyle {
    let baseFont: Font
    let codeFont: Font
    let headingFonts: [Font]
    let linkColor: Color
    let textColor: Color
    let codeTextColor: Color
    let codeBackgroundColor: Color
    let quoteStripeColor: Color
    let blockSpacing: CGFloat
    let listIndent: CGFloat
}

struct MarkdownDocument: Equatable, Sendable {
    fileprivate let source: String
    fileprivate let options: ParseOptions
}

struct MarkdownParser {
    func parse(_ markdown: String, options: ParseOptions) throws -> MarkdownDocument {
        MarkdownDocument(source: markdown, options: options)
    }
}

struct IncrementalMarkdownParser {
    struct Configuration {
        let options: ParseOptions
        let minBufferSize: Int
    }

    private let configuration: Configuration
    private var buffer = ""

    init(configuration: Configuration) {
        self.configuration = configuration
        self.buffer.reserveCapacity(max(configuration.minBufferSize, 0))
    }

    mutating func append(_ fragment: String) -> MarkdownDocument {
        buffer.append(fragment)
        return MarkdownDocument(source: buffer, options: configuration.options)
    }

    mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    mutating func finalize() -> MarkdownDocument {
        MarkdownDocument(source: buffer, options: configuration.options)
    }
}

struct AttributedStringRenderer {
    func render(_ document: MarkdownDocument, style: MarkdownStyle) -> AttributedString {
        let sanitized = sanitize(document.source, options: document.options)

        let parsed = (try? AttributedString(
            markdown: sanitized,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(sanitized)

        var result = parsed
        if !result.characters.isEmpty {
            let range = result.startIndex..<result.endIndex
            result[range].font = style.baseFont
            result[range].foregroundColor = style.textColor
        }
        return result
    }

    private func sanitize(_ markdown: String, options: ParseOptions) -> String {
        guard options.contains(.noHTMLBlocks) || options.contains(.noHTMLSpans) else {
            return markdown
        }

        return markdown.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
    }
}
