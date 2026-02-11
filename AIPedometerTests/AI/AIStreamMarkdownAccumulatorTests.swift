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
}
