import Foundation

public struct ImportedArtifact: Equatable {
    public let paperID: String
    public let type: ArtifactType
    public let contentMarkdown: String

    public init(paperID: String, type: ArtifactType, contentMarkdown: String) {
        self.paperID = paperID
        self.type = type
        self.contentMarkdown = contentMarkdown
    }
}

public enum ClipboardImportError: LocalizedError, Equatable {
    case malformedWrapper(String)

    public var errorDescription: String? {
        switch self {
        case .malformedWrapper(let message):
            return message
        }
    }
}

public struct ClipboardImportParser {
    public init() {}

    public func parse(_ text: String) throws -> [ImportedArtifact] {
        var artifacts: [ImportedArtifact] = []
        artifacts.append(contentsOf: try parse(
            text,
            type: .summary,
            beginLabel: "BEGIN PAPER SUMMARY",
            endLabel: "END PAPER SUMMARY"
        ))
        artifacts.append(contentsOf: try parse(
            text,
            type: .studyGuide,
            beginLabel: "BEGIN STUDY GUIDE",
            endLabel: "END STUDY GUIDE"
        ))
        return artifacts
    }

    private func parse(
        _ text: String,
        type: ArtifactType,
        beginLabel: String,
        endLabel: String
    ) throws -> [ImportedArtifact] {
        let escapedBegin = NSRegularExpression.escapedPattern(for: beginLabel)
        let escapedEnd = NSRegularExpression.escapedPattern(for: endLabel)
        let paperIDPattern = #"P-\d{4}-\d{2}-\d{2}-\d{4}"#
        let beginPattern = #"\["# + escapedBegin + #":\s*("# + paperIDPattern + #")\]"#
        let endPattern = #"\["# + escapedEnd + #":\s*("# + paperIDPattern + #")\]"#
        let beginRegex = try NSRegularExpression(pattern: beginPattern)
        let endRegex = try NSRegularExpression(pattern: endPattern)
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let begins = beginRegex.matches(in: text, range: fullRange)

        var artifacts: [ImportedArtifact] = []
        for begin in begins {
            let paperID = try capture(1, in: begin, text: text)
            let searchRange = NSRange(
                location: begin.range.location + begin.range.length,
                length: fullRange.length - begin.range.location - begin.range.length
            )

            guard let end = endRegex.firstMatch(in: text, range: searchRange) else {
                throw ClipboardImportError.malformedWrapper("Found a malformed wrapper. The BEGIN wrapper has no matching END wrapper.")
            }

            let endPaperID = try capture(1, in: end, text: text)
            guard paperID == endPaperID else {
                throw ClipboardImportError.malformedWrapper("Found a malformed wrapper. The BEGIN and END paper IDs do not match.")
            }

            guard let contentStart = Range(begin.range, in: text)?.upperBound,
                  let contentEnd = Range(end.range, in: text)?.lowerBound else {
                throw ClipboardImportError.malformedWrapper("Found a malformed wrapper that could not be parsed.")
            }

            let content = String(text[contentStart..<contentEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            artifacts.append(ImportedArtifact(
                paperID: paperID,
                type: type,
                contentMarkdown: content
            ))
        }

        return artifacts
    }

    private func capture(_ index: Int, in match: NSTextCheckingResult, text: String) throws -> String {
        guard let range = Range(match.range(at: index), in: text) else {
            throw ClipboardImportError.malformedWrapper("Found a malformed wrapper that could not be parsed.")
        }
        return String(text[range])
    }
}
