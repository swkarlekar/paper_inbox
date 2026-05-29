import Foundation

enum LibraryFilter: Hashable, Identifiable {
    case inbox
    case toStudy
    case read
    case archived
    case all
    case collection(String)

    var id: String {
        switch self {
        case .inbox:
            return "inbox"
        case .toStudy:
            return "toStudy"
        case .read:
            return "read"
        case .archived:
            return "archived"
        case .all:
            return "all"
        case .collection(let id):
            return "collection:\(id)"
        }
    }
}

struct AlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
