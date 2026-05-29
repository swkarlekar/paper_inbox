import Foundation

public struct PaperCollection: Identifiable, Codable, Equatable {
    public let id: String
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PaperCollectionMembership: Codable, Equatable, Hashable {
    public let paperID: String
    public let collectionID: String

    public init(paperID: String, collectionID: String) {
        self.paperID = paperID
        self.collectionID = collectionID
    }
}
