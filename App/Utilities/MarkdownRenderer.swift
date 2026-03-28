import Foundation

enum MarkdownSegment: Equatable {
    case prose(AttributedString)
    case codeBlock(language: String?, code: String)
}

enum MarkdownRenderer {
    static func segments(from markdown: String) -> [MarkdownSegment] {
        guard markdown.contains("```") else {
            return [.prose(attributed(markdown))]
        }

        var segments: [MarkdownSegment] = []
        var currentIndex = markdown.startIndex

        while currentIndex < markdown.endIndex {
            guard let fenceStart = markdown.range(of: "```", range: currentIndex..<markdown.endIndex) else {
                appendProse(String(markdown[currentIndex...]), to: &segments)
                break
            }

            appendProse(String(markdown[currentIndex..<fenceStart.lowerBound]), to: &segments)

            let contentStart = fenceStart.upperBound
            guard let fenceEnd = markdown.range(of: "```", range: contentStart..<markdown.endIndex) else {
                appendProse(String(markdown[fenceStart.lowerBound...]), to: &segments)
                break
            }

            let language: String?
            let code: String

            let fencedSlice = markdown[contentStart..<fenceEnd.lowerBound]
            if let firstNewline = fencedSlice.firstIndex(of: "\n") {
                let infoString = fencedSlice[fencedSlice.startIndex..<firstNewline]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                language = infoString.isEmpty ? nil : String(infoString)
                code = String(fencedSlice[fencedSlice.index(after: firstNewline)...])
                    .trimmingCharacters(in: .newlines)
            } else {
                language = nil
                code = String(fencedSlice).trimmingCharacters(in: .newlines)
            }

            segments.append(.codeBlock(language: language, code: code))
            currentIndex = fenceEnd.upperBound
        }

        return segments.isEmpty ? [.prose(attributed(markdown))] : segments
    }

    private static func appendProse(_ text: String, to segments: inout [MarkdownSegment]) {
        guard !text.isEmpty else {
            return
        }

        segments.append(.prose(attributed(text)))
    }

    private static func attributed(_ markdown: String) -> AttributedString {
        if let parsed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            return parsed
        }

        return AttributedString(markdown)
    }
}
