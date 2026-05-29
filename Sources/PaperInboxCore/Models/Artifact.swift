import Foundation

public struct Artifact: Identifiable, Codable, Equatable {
    public let id: String
    public let paperID: String
    public let type: ArtifactType
    public var contentMarkdown: String
    public var source: ArtifactSource
    public var chatGPTURL: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        paperID: String,
        type: ArtifactType,
        contentMarkdown: String,
        source: ArtifactSource,
        chatGPTURL: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.paperID = paperID
        self.type = type
        self.contentMarkdown = contentMarkdown
        self.source = source
        self.chatGPTURL = chatGPTURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
