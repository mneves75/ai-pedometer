import Foundation
import Testing

@testable import AIPedometer

@Suite("AIChatMarkdown Tests")
struct AIChatMarkdownTests {
    @Test("Strips raw HTML tags without mangling angle-bracket comparisons in coaching prose")
    func disablesRawHTMLWithoutManglingComparisons() throws {
        let htmlDoc = try AIChatMarkdown.parseDocument(
            from: #"Hello <script>alert(1)</script> world <a href="https://evil.test">tap</a><!-- secret -->"#
        )
        let htmlRendered = String(AIChatMarkdown.renderAttributedString(from: htmlDoc).characters)
        #expect(!htmlRendered.contains("<script>"))
        #expect(!htmlRendered.contains("</script>"))
        #expect(!htmlRendered.contains("<a "))
        #expect(!htmlRendered.contains("<!--"))
        #expect(htmlRendered.contains("Hello"))
        #expect(htmlRendered.contains("world"))

        let prose = "If steps < 5,000 and > 2,000, add a short walk."
        let proseDoc = try AIChatMarkdown.parseDocument(from: prose)
        let proseRendered = String(AIChatMarkdown.renderAttributedString(from: proseDoc).characters)
        #expect(proseRendered.contains("< 5,000 and > 2,000"))
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
