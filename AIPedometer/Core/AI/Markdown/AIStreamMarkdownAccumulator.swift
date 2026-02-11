import SwiftFastMarkdown

/// Incremental markdown parsing helper for streaming content.
///
/// Rationale:
/// - Keep the "prefix append vs reset" logic out of CoachService (testable, small surface area)
/// - Reuse SwiftFastMarkdown's incremental parser for speed
struct AIStreamMarkdownAccumulator {
    private var parser: IncrementalMarkdownParser
    private var lastContent: String = ""

    init(minBufferSize: Int = 32) {
        self.parser = AIChatMarkdown.makeIncrementalParser(minBufferSize: minBufferSize)
    }

    mutating func reset() {
        lastContent = ""
        parser.reset()
    }

    /// Ingests the latest full content (not a delta) and returns an updated document when needed.
    ///
    /// The stream sometimes re-sends the full prefix (common with streaming LLM APIs).
    /// If the content isn't a strict append of the previous value, we reset and re-parse to recover.
    mutating func ingest(fullContent: String) -> MarkdownDocument? {
        if fullContent == lastContent {
            return nil
        }

        let document: MarkdownDocument
        if !lastContent.isEmpty && fullContent.hasPrefix(lastContent) {
            let appended = String(fullContent.dropFirst(lastContent.count))
            document = parser.append(appended)
        } else {
            parser.reset()
            document = parser.append(fullContent)
        }

        lastContent = fullContent
        return document
    }

    mutating func finalize() -> MarkdownDocument {
        parser.finalize()
    }
}

