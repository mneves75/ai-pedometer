/// Applies full streaming snapshots to the local incremental Markdown parser.
struct AIStreamMarkdownAccumulator {
    private var parser: IncrementalMarkdownParser
    private var lastContent: String = ""
    private var lastContentUTF8Count = 0

    init(minBufferSize: Int = 32) {
        self.parser = AIChatMarkdown.makeIncrementalParser(minBufferSize: minBufferSize)
    }

    mutating func reset() {
        lastContent = ""
        lastContentUTF8Count = 0
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

        let fullContentUTF8 = fullContent.utf8
        let prefixMatches = fullContentUTF8.withContiguousStorageIfAvailable { fullBuffer in
            lastContent.utf8.withContiguousStorageIfAvailable { lastBuffer in
                fullBuffer.starts(with: lastBuffer)
            } ?? false
        } ?? false
        let isStrictUTF8Append = !lastContent.isEmpty
            && fullContentUTF8.count > lastContentUTF8Count
            && prefixMatches

        let document: MarkdownDocument
        if isStrictUTF8Append {
            let suffix = fullContentUTF8.dropFirst(lastContentUTF8Count)
            let appended = String(decoding: suffix, as: UTF8.self)
            document = parser.append(appended)
        } else {
            parser.reset()
            document = parser.append(fullContent)
        }

        lastContent = fullContent
        lastContentUTF8Count = fullContentUTF8.count
        return document
    }

    mutating func finalize() -> MarkdownDocument {
        parser.finalize()
    }
}
