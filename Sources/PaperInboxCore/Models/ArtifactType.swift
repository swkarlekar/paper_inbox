import Foundation

public enum ArtifactType: String, Codable, CaseIterable, Identifiable {
    case summary
    case studyGuide
    case chatTranscript
    case notes

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .summary:
            return "Summary"
        case .studyGuide:
            return "Study Guide"
        case .chatTranscript:
            return "Chat Transcript"
        case .notes:
            return "Notes"
        }
    }

    public var markdownFilename: String {
        switch self {
        case .summary:
            return "summary.md"
        case .studyGuide:
            return "study_guide.md"
        case .chatTranscript:
            return "chat_transcript.md"
        case .notes:
            return "notes.md"
        }
    }
}

public enum ArtifactSource: String, Codable, CaseIterable, Identifiable {
    case clipboard
    case chatGPTExport
    case manual

    public var id: String { rawValue }
}
