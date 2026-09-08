import Testing

@testable import AIPedometer

@Suite("AIStreamMarkdownAccumulator Tests")
struct AIStreamMarkdownAccumulatorTests {
    @Test("Ignores duplicate content updates")
    func ignoresDuplicateUpdates() {
        var accumulator = AIStreamMarkdownAccumulator()

        let firstDocument = accumulator.ingest(fullContent: "Hello **world**")
        #expect(firstDocument != nil)

        let duplicateDocument = accumulator.ingest(fullContent: "Hello **world**")
        #expect(duplicateDocument == nil)
    }

    @Test("Resets parser when stream content diverges from previous prefix")
    func resetsWhenContentDiverges() throws {
        var accumulator = AIStreamMarkdownAccumulator()

        _ = accumulator.ingest(fullContent: "Hello **wor")
        _ = accumulator.ingest(fullContent: "Completely _different_ content")

        let incrementalFinal = accumulator.finalize()
        let incrementalRendered = AIChatMarkdown.renderAttributedString(from: incrementalFinal)

        let expectedDocument = try AIChatMarkdown.parseDocument(from: "Completely _different_ content")
        let expectedRendered = AIChatMarkdown.renderAttributedString(from: expectedDocument)

        #expect(String(incrementalRendered.characters) == String(expectedRendered.characters))
    }

    @Test("Preserves Unicode sequences whose grapheme boundary changes while streaming")
    func preservesUnicodeBoundaryExtensions() throws {
        let streams = [
            ["e", "e\u{301}", "e\u{301}lan"],
            ["❤", "❤️", "❤️ done"],
            ["🇺", "🇺🇸", "🇺🇸 route"],
            ["👩", "👩‍", "👩‍💻", "👩‍💻 plan"]
        ]

        for stream in streams {
            var accumulator = AIStreamMarkdownAccumulator()
            for snapshot in stream {
                _ = accumulator.ingest(fullContent: snapshot)
            }

            let incrementalRendered = AIChatMarkdown.renderAttributedString(from: accumulator.finalize())
            let expectedDocument = try AIChatMarkdown.parseDocument(from: #require(stream.last))
            let expectedRendered = AIChatMarkdown.renderAttributedString(from: expectedDocument)

            #expect(String(incrementalRendered.characters) == String(expectedRendered.characters))
        }
    }

    @Test("Resets safely when a canonical-equivalent prefix changes UTF-8 representation")
    func resetsForCanonicalEquivalentUTF8Rewrite() throws {
        var accumulator = AIStreamMarkdownAccumulator()

        _ = accumulator.ingest(fullContent: "é")
        _ = accumulator.ingest(fullContent: "e\u{301}x")

        let incrementalRendered = AIChatMarkdown.renderAttributedString(from: accumulator.finalize())
        let expectedDocument = try AIChatMarkdown.parseDocument(from: "e\u{301}x")
        let expectedRendered = AIChatMarkdown.renderAttributedString(from: expectedDocument)

        #expect(String(incrementalRendered.characters) == String(expectedRendered.characters))
    }

    @Test("Resets safely when an ASCII prefix is canonically equivalent to a multibyte scalar")
    func resetsForASCIIConfusableUTF8Rewrite() throws {
        var accumulator = AIStreamMarkdownAccumulator()

        _ = accumulator.ingest(fullContent: "K")
        _ = accumulator.ingest(fullContent: "Kx")

        let incrementalRendered = AIChatMarkdown.renderAttributedString(from: accumulator.finalize())
        let expectedDocument = try AIChatMarkdown.parseDocument(from: "Kx")
        let expectedRendered = AIChatMarkdown.renderAttributedString(from: expectedDocument)

        #expect(String(incrementalRendered.characters) == String(expectedRendered.characters))
    }
}
