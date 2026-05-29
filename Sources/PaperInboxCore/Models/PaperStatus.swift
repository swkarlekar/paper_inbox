import Foundation

public enum PaperStatus: String, Codable, CaseIterable, Identifiable {
    case unread
    case toStudy
    case read
    case archived

    public var id: String { rawValue }

    public static func fromStoredValue(_ value: String) -> PaperStatus {
        switch value {
        case PaperStatus.toStudy.rawValue:
            return .toStudy
        case PaperStatus.read.rawValue:
            return .read
        case PaperStatus.archived.rawValue:
            return .archived
        default:
            // Older builds used ChatGPT workflow states here. Artifact presence now
            // carries that information, so legacy workflow states become Inbox papers.
            return .unread
        }
    }

    public var displayName: String {
        switch self {
        case .unread:
            return "Unread"
        case .toStudy:
            return "To Study"
        case .read:
            return "Read"
        case .archived:
            return "Archived"
        }
    }

    public var isHiddenByDefault: Bool {
        self == .read || self == .archived
    }
}
