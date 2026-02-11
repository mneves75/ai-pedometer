import Foundation
import SwiftFastMarkdown
import Testing

@testable import AIPedometer

@Suite("AIChatMarkdown Tests")
struct AIChatMarkdownTests {
    @Test("Disables raw HTML parsing")
    func disablesRawHTML() {
        #expect(AIChatMarkdown.parseOptions.contains(.noHTMLBlocks))
        #expect(AIChatMarkdown.parseOptions.contains(.noHTMLSpans))
    }

    @Test("Incremental streaming render matches full render (plain text + links)")
    func incrementalRenderMatchesFullRender() throws {
        let full = """
        Hello **world**

        - item 1
        - item 2

        `code`

        [link](https://example.com)
        """

        var accumulator = AIStreamMarkdownAccumulator()

        let chunks = [
            "Hello **w",
            "Hello **world**\n\n- item 1",
            "Hello **world**\n\n- item 1\n- item 2\n\n`code`",
            full
        ]

        for chunk in chunks {
            _ = accumulator.ingest(fullContent: chunk)
        }

        let incrementalDoc = accumulator.finalize()
        let incrementalAttr = AIChatMarkdown.renderAttributedString(from: incrementalDoc)

        let fullDoc = try AIChatMarkdown.parseDocument(from: full)
        let fullAttr = AIChatMarkdown.renderAttributedString(from: fullDoc)

        #expect(String(incrementalAttr.characters) == String(fullAttr.characters))
        #expect(linkCount(incrementalAttr) == linkCount(fullAttr))
        #expect(linkCount(fullAttr) >= 1)
    }

    private func linkCount(_ attributed: AttributedString) -> Int {
        var count = 0
        for run in attributed.runs {
            if run.link != nil {
                count += 1
            }
        }
        return count
    }
}

